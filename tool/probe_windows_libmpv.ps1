param(
  # libmpv-2.dll to load; by default the release bundle's copy.
  [string]$Dll = (Join-Path $env:USERPROFILE 'develop\klipa-player-windows-native\build\windows\x64\runner\Release\libmpv-2.dll'),
  # Public HTTPS test streams, tried in order until one plays.
  [string]$Playlist = (Join-Path $PSScriptRoot '..\packaging\windows\store\certification-test.m3u'),
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\dist\windows-store\probe\libmpv-https-probe.json'),
  [int]$TimeoutSeconds = 30
)

# Release gate for the Windows media runtime: libmpv must play a public HTTPS
# stream with the network options Klipa's player sets, TLS certificate
# verification included, so the trust store the DLL's TLS backend uses is
# exercised. No video or audio output is opened, which keeps the window, GPU
# and Flutter layers out of the result. If no stream plays, the first one is
# retried with verification off to tell a TLS failure from a network one.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$dllPath = (Resolve-Path -LiteralPath $Dll).Path

if (-not ('KlipaMpvProbe' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class KlipaMpvProbe {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool SetDllDirectory(string path);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern IntPtr mpv_create();
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern int mpv_initialize(IntPtr handle);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern int mpv_set_option_string(IntPtr handle, byte[] name, byte[] value);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern int mpv_request_log_messages(IntPtr handle, byte[] level);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern int mpv_command(IntPtr handle, IntPtr[] args);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern IntPtr mpv_wait_event(IntPtr handle, double timeout);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern IntPtr mpv_get_property_string(IntPtr handle, byte[] name);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern void mpv_free(IntPtr data);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern IntPtr mpv_error_string(int error);
  [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
  static extern void mpv_terminate_destroy(IntPtr handle);

  static byte[] Z(string value) { return Encoding.UTF8.GetBytes(value + "\0"); }

  static string S(IntPtr text) {
    if (text == IntPtr.Zero) return null;
    var length = 0;
    while (Marshal.ReadByte(text, length) != 0) length++;
    var bytes = new byte[length];
    Marshal.Copy(text, bytes, 0, length);
    return Encoding.UTF8.GetString(bytes);
  }

  public static void UseDirectory(string directory) { SetDllDirectory(directory); }

  public static Dictionary<string, object> Run(string url, string[] options, int timeoutSeconds) {
    var result = new Dictionary<string, object>();
    var log = new List<string>();
    var handle = mpv_create();
    if (handle == IntPtr.Zero) throw new InvalidOperationException("mpv_create failed");
    try {
      foreach (var option in options) {
        var split = option.IndexOf('=');
        var status = mpv_set_option_string(handle, Z(option.Substring(0, split)), Z(option.Substring(split + 1)));
        if (status < 0) log.Add("option " + option + ": " + S(mpv_error_string(status)));
      }
      mpv_request_log_messages(handle, Z("v"));
      var init = mpv_initialize(handle);
      if (init < 0) throw new InvalidOperationException("mpv_initialize: " + S(mpv_error_string(init)));
      var version = mpv_get_property_string(handle, Z("ffmpeg-version"));
      result["ffmpegVersion"] = S(version);
      mpv_free(version);

      var argv = new[] { Marshal.AllocHGlobal(16), Marshal.AllocHGlobal(Encoding.UTF8.GetByteCount(url) + 1), IntPtr.Zero };
      var loadfile = Z("loadfile");
      Marshal.Copy(loadfile, 0, argv[0], loadfile.Length);
      var target = Z(url);
      Marshal.Copy(target, 0, argv[1], target.Length);
      var command = mpv_command(handle, argv);
      Marshal.FreeHGlobal(argv[0]);
      Marshal.FreeHGlobal(argv[1]);
      if (command < 0) throw new InvalidOperationException("loadfile: " + S(mpv_error_string(command)));

      var outcome = "timeout";
      var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
      while (DateTime.UtcNow < deadline && outcome == "timeout") {
        var ev = mpv_wait_event(handle, 0.5);
        var id = Marshal.ReadInt32(ev, 0);
        var data = Marshal.ReadIntPtr(ev, 16);
        switch (id) {
          case 2: {
            var level = S(Marshal.ReadIntPtr(data, 8));
            var line = "[" + S(Marshal.ReadIntPtr(data, 0)) + "] " + level + ": " + (S(Marshal.ReadIntPtr(data, 16)) ?? "").TrimEnd();
            var lower = line.ToLowerInvariant();
            if (level == "fatal" || level == "error" || level == "warn" || lower.Contains("tls") || lower.Contains("ssl")
                || lower.Contains("certificate") || lower.Contains("whitelist") || lower.Contains("opening")) {
              if (log.Count < 200) log.Add(line);
            }
            break;
          }
          case 7: {
            var reason = Marshal.ReadInt32(data, 0);
            var error = Marshal.ReadInt32(data, 4);
            outcome = "end-file reason " + reason + (error < 0 ? ": " + S(mpv_error_string(error)) : "");
            break;
          }
          case 8: result["fileLoaded"] = true; break;
          case 21: outcome = "playing"; break;
        }
      }
      result["outcome"] = outcome;
    } finally {
      mpv_terminate_destroy(handle);
    }
    result["log"] = log;
    return result;
  }
}
'@
}

[KlipaMpvProbe]::UseDirectory((Split-Path -Parent $dllPath))

$urls = @(Get-Content -LiteralPath $Playlist | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^https://' })
if ($urls.Count -eq 0) { throw "No https stream in $Playlist" }

# The options MediaKitVideoPlayerPort sets, without video or audio output.
$klipa = @(
  'vo=null', 'ao=null', 'load-scripts=no', 'load-unsafe-playlists=no',
  'cookies=no', 'network-timeout=20', 'tls-verify=yes',
  'demuxer-lavf-o=protocol_whitelist=[tcp,tls,http,https,crypto]'
)

function Invoke-Probe([string]$Url, [string[]]$Options) {
  try {
    return [KlipaMpvProbe]::Run($Url, $Options, $TimeoutSeconds)
  } catch {
    return @{ outcome = "probe failed: $($_.Exception.Message)"; log = @() }
  }
}

$results = [ordered]@{
  dll = $dllPath
  dllSha256 = (Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash.ToLowerInvariant()
  attempts = @()
  passed = $false
}
foreach ($url in $urls) {
  $attempt = Invoke-Probe $url $klipa
  $results.attempts += [ordered]@{ url = $url; options = 'as Klipa'; result = $attempt }
  "as Klipa, ${url}: $($attempt['outcome'])"
  if ($attempt['outcome'] -eq 'playing') { $results.passed = $true; break }
}
if (-not $results.passed) {
  $plain = $klipa | ForEach-Object { if ($_ -eq 'tls-verify=yes') { 'tls-verify=no' } else { $_ } }
  $diagnostic = Invoke-Probe $urls[0] $plain
  $results.attempts += [ordered]@{ url = $urls[0]; options = 'as Klipa, tls-verify=no'; result = $diagnostic }
  "tls-verify=no, $($urls[0]): $($diagnostic['outcome'])"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
if (-not $results.passed) {
  Get-Content -LiteralPath $OutputPath
  throw 'The media runtime played no HTTPS test stream with TLS verification on.'
}
"Probe passed: $OutputPath"
