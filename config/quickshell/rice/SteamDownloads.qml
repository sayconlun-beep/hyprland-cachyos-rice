pragma Singleton

// What Steam is downloading, for the lock screen. Steam has no API for this,
// so it is pieced together from its own files every 3 s, and only while
// something is watching:
//
//   which app, and doing what   the last "App update changed" line in
//                               logs/content_log.txt ("Running Update,
//                               Downloading,..." while busy, "None" when not)
//   totals                      that app's "update started" line
//   progress                    the disk space actually written under
//                               steamapps/downloading/<appid>, over the stage
//                               total. Steam writes sparse files and (here)
//                               preallocates nothing, so blocks track progress
//                               live; the appmanifest only updates on pause.
//   speed                       the log's once-a-minute "Current download rate"
//   name, art                   the appmanifest and appcache/librarycache
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool watched: false

    property bool active: false
    property string appid: ""
    property string name: ""
    property string status: ""               // Downloading, Verifying, Installing, Updating
    property real progress: 0                // 0..1
    property real rate: 0                    // Mbit/s, 0 when unknown
    property real downloadTotal: 0           // bytes
    property string art: ""                  // file path of the library header

    readonly property string etaText: {
        if (status !== "Downloading" || rate <= 0 || downloadTotal <= 0)
            return ""
        const s = downloadTotal * (1 - progress) * 8 / (rate * 1e6)
        const m = Math.ceil(s / 60)
        return m < 60 ? m + " min left" : Math.floor(m / 60) + " h " + m % 60 + " min left"
    }

    readonly property string sampleScript: `
steam="$HOME/.local/share/Steam"
log="$steam/logs/content_log.txt"
[ -r "$log" ] && pgrep -x steam >/dev/null || exit 0
last=$(tail -n 800 "$log" | grep -E 'AppID [0-9]+ App update changed : ' | tail -n1)
case "$last" in *"Running Update"*) ;; *) exit 0 ;; esac
id=$(sed -E 's/.*AppID ([0-9]+) .*/\\1/' <<<"$last")
echo "app $id"
echo "flags \${last##*: }"
started=$(tail -n 4000 "$log" | grep -E "AppID $id update started : " | tail -n1)
echo "download $(sed -nE 's/.*download [0-9]+\\/([0-9]+).*/\\1/p' <<<"$started")"
echo "stage $(sed -nE 's/.*stage ([0-9]+)\\/([0-9]+).*/\\1 \\2/p' <<<"$started")"
rl=$(tail -n 200 "$log" | grep 'Current download rate' | tail -n1)
if [ -n "$rl" ]; then
    t=$(date -d "$(sed -E 's/^\\[([^]]+)\\].*/\\1/' <<<"$rl")" +%s 2>/dev/null)
    [ -n "$t" ] && [ $(( $(date +%s) - t )) -lt 150 ] && echo "rate $(sed -E 's/.*rate: ([0-9.]+).*/\\1/' <<<"$rl")"
fi
libs=$(sed -nE 's/^\\s*"path"\\s+"(.*)"/\\1/p' "$steam/steamapps/libraryfolders.vdf")
while IFS= read -r lib; do
    m="$lib/steamapps/appmanifest_$id.acf"
    [ -r "$m" ] || continue
    echo "name $(sed -nE 's/^\\s*"name"\\s+"(.*)"/\\1/p' "$m")"
    d="$lib/steamapps/downloading/$id"
    [ -d "$d" ] && echo "written $(du -s --block-size=1 "$d" | cut -f1)"
    break
done <<<"$libs"
art=$(find "$steam/appcache/librarycache/$id" -name 'library_header.jpg' 2>/dev/null | head -n1)
[ -z "$art" ] && art=$(ls "$steam/appcache/librarycache/$id"_header.jpg 2>/dev/null)
echo "art $art"
`

    Timer {
        interval: 3000
        repeat: true
        running: root.watched
        triggeredOnStart: true
        onTriggered: if (!sampler.running) sampler.running = true
    }

    Process {
        id: sampler
        command: ["bash", "-c", root.sampleScript]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    function parse(text) {
        const v = {}
        for (const line of text.split("\n")) {
            const key = line.split(" ")[0]
            if (key)
                v[key] = line.slice(key.length + 1).trim()
        }
        if (!v.app) {
            active = false
            return
        }
        const flags = v.flags || ""
        status = flags.includes("Downloading") ? "Downloading"
               : /Verifying|Validating/.test(flags) ? "Verifying"
               : /Committing|Staging/.test(flags) ? "Installing"
               : "Updating"
        const stage = (v.stage || "").split(" ").map(Number)
        const stageTotal = stage[1] || 0
        const written = Number(v.written || 0)
        let p = stageTotal ? Math.max(written, stage[0] || 0) / stageTotal : 0
        progress = Math.min(p, 0.999)
        rate = Number(v.rate || 0)
        downloadTotal = Number(v.download || 0)
        appid = v.app
        name = v.name || "App " + v.app
        art = v.art || ""
        active = true
    }

    function gib(bytes) {
        return (bytes / 1073741824).toFixed(1) + " GB"
    }
}
