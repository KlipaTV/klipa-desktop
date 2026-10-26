#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <cstring>

namespace {

constexpr char kWindowChannel[] = "dev.klipa.player/window";

// How long a full-screen request waits for the window manager to confirm it
// before answering with the state the window actually has.
constexpr guint kFullscreenConfirmTimeoutMs = 1500;

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* window_channel;
  gboolean is_fullscreen;
  // A full-screen request is answered once the window manager reports the
  // new state, so Dart never shows a mode the window did not enter.
  FlMethodCall* pending_fullscreen_call;
  guint pending_fullscreen_timeout;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void respond_fullscreen(FlMethodCall* method_call, gboolean value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(method_call, response, nullptr);
}

static void finish_pending_fullscreen(MyApplication* self) {
  if (self->pending_fullscreen_timeout != 0) {
    g_source_remove(self->pending_fullscreen_timeout);
    self->pending_fullscreen_timeout = 0;
  }
  if (self->pending_fullscreen_call != nullptr) {
    respond_fullscreen(self->pending_fullscreen_call, self->is_fullscreen);
    g_clear_object(&self->pending_fullscreen_call);
  }
}

static gboolean fullscreen_confirm_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->pending_fullscreen_timeout = 0;
  finish_pending_fullscreen(self);
  return G_SOURCE_REMOVE;
}

static void set_fullscreen(MyApplication* self, FlMethodCall* method_call,
                           gboolean enabled) {
  // A newer request supersedes an unanswered one.
  finish_pending_fullscreen(self);
  if (enabled == self->is_fullscreen) {
    respond_fullscreen(method_call, self->is_fullscreen);
    return;
  }
  self->pending_fullscreen_call = FL_METHOD_CALL(g_object_ref(method_call));
  self->pending_fullscreen_timeout = g_timeout_add(
      kFullscreenConfirmTimeoutMs, fullscreen_confirm_timeout_cb, self);
  if (enabled) {
    gtk_window_fullscreen(self->window);
  } else {
    gtk_window_unfullscreen(self->window);
  }
}

static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "setFullscreen") == 0) {
    FlValue* arguments = fl_method_call_get_args(method_call);
    if (arguments == nullptr ||
        fl_value_get_type(arguments) != FL_VALUE_TYPE_BOOL) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "invalid_argument", "setFullscreen requires a boolean value.",
              nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    set_fullscreen(self, method_call, fl_value_get_bool(arguments));
    return;
  }
  if (strcmp(method, "isFullscreen") == 0) {
    respond_fullscreen(method_call, self->is_fullscreen);
    return;
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

// The window manager can leave full screen on its own (a workspace switch or
// its own shortcut), so every confirmed change is pushed to Dart.
static gboolean window_state_cb(GtkWidget* widget, GdkEventWindowState* event,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if ((event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) == 0) return FALSE;
  const gboolean fullscreen =
      (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  if (fullscreen == self->is_fullscreen) return FALSE;
  self->is_fullscreen = fullscreen;
  finish_pending_fullscreen(self);
  if (self->window_channel != nullptr) {
    g_autoptr(FlValue) value = fl_value_new_bool(fullscreen);
    fl_method_channel_invoke_method(self->window_channel, "fullscreenChanged",
                                    value, nullptr, nullptr, nullptr);
  }
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Klipa Player");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Klipa Player");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // The window uses the mark shipped in the bundle's own assets, so a bundle
  // run outside the installed package still shows the Klipa icon.
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon_path =
        g_build_filename(directory, "data", "flutter_assets", "assets",
                         "branding", "logo_mark.png", nullptr);
    gtk_window_set_icon_from_file(window, icon_path, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  self->window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kWindowChannel,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, self, nullptr);
  g_signal_connect(window, "window-state-event", G_CALLBACK(window_state_cb),
                   self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->pending_fullscreen_timeout != 0) {
    g_source_remove(self->pending_fullscreen_timeout);
    self->pending_fullscreen_timeout = 0;
  }
  g_clear_object(&self->pending_fullscreen_call);
  g_clear_object(&self->window_channel);
  self->window = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
