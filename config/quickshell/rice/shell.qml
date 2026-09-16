// The rice's Quickshell layer.
//
//   qs -c rice ipc call dashboard toggle        dashboard (Super+D, bar clock)
//   qs -c rice ipc call capture menu            screenshot / record (Super+Shift+S)
//   qs -c rice ipc call controlcenter toggle    control centre (network/volume pill)
//   qs -c rice ipc call notifications toggle    notification centre (Super+N, bell)
//   qs -c rice ipc call settings toggle         settings hub (bar gear, Super+,)
//   qs -c rice ipc call wallpaper toggle        carousel (Super+Shift+W)
//   qs -c rice ipc call wallhaven toggle        wallhaven search + filters (Super+Ctrl+W)
//   qs -c rice ipc call binds toggle            keybind cheatsheet + editor (Super+/)
//   qs -c rice ipc call displays toggle         drag screens into place (Settings › Displays)
//   qs -c rice ipc call visualiser toggle       desktop cava (Super+Shift+V)
//   qs -c rice ipc call clock toggle            desktop clock
//   qs -c rice ipc call lyrics toggle           desktop lyrics
//
// Started from autostart.conf with `qs -c rice -n -d`. It is also the
// notification daemon (NotifService.qml). Apart from the clock and the
// visualiser, windows exist only while open, and only one overlay is open at
// a time - opening one closes the rest.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell

    WallpaperCarousel { id: walls }
    Wallhaven { id: wallhaven }
    Keybinds { id: binds }
    Displays { id: displays }
    Visualiser { id: visualiser }
    DesktopClock { id: clock }
    DesktopLyrics {
        id: lyrics
        visualiser: visualiser
    }
    Osd {}
    NotificationPopups {}
    NotificationCenter { id: notifs }
    Capture { id: capture }
    Lock { id: locker }
    CaptureMenu {
        id: captureMenu
        capture: capture
    }
    Dashboard {
        id: dash
        visualiser: visualiser
    }
    ControlCenter {
        id: cc
        visualiser: visualiser
    }
    SettingsMenu {
        id: settings
        visualiser: visualiser
        clock: clock
        lyrics: lyrics
        walls: walls
        binds: binds
        displays: displays
        controlCenter: cc
        notifications: notifs
        dashboard: dash
        captureMenu: captureMenu
    }

    function closeOthers(keep) {
        if (keep !== walls) walls.cancel()
        if (keep !== wallhaven) wallhaven.close()
        if (keep !== binds) binds.close()
        if (keep !== displays) displays.close()
        if (keep !== cc) cc.close()
        if (keep !== settings) settings.close()
        if (keep !== notifs) notifs.close()
        if (keep !== dash) dash.close()
        if (keep !== captureMenu) captureMenu.close()
    }

    // Lock, preview and status only - deliberately nothing that unlocks.
    IpcHandler {
        target: "lock"
        function lock(): void { shell.closeOthers(null); locker.lock() }
        function preview(): void { shell.closeOthers(null); locker.preview() }
        function endPreview(): void { locker.endPreview() }   // the preview locks nothing
        function status(): string { return locker.locked ? "locked" : locker.previewing ? "preview" : "unlocked" }
    }

    IpcHandler {
        target: "capture"
        function menu(): void { shell.closeOthers(captureMenu); captureMenu.toggle() }
        // screen | window | area
        function screenshot(mode: string): void { shell.closeOthers(null); capture.screenshot(mode) }
        // screen | area
        function record(mode: string): void { shell.closeOthers(null); capture.record(mode) }
        function stop(): void { capture.stop() }
        function toggleRecording(): void { shell.closeOthers(null); capture.toggleRecording() }
        function status(): string { return capture.recording ? "recording " + capture.elapsedText : "idle" }
    }

    IpcHandler {
        target: "dashboard"
        function toggle(): void { shell.closeOthers(dash); dash.toggle() }
        function open(): void { shell.closeOthers(dash); dash.show() }
        function close(): void { dash.close() }
        // overview | media | weather | alerts | system | productivity
        function tab(name: string): void { shell.closeOthers(dash); dash.showTab(name) }
        // For checking the GitHub tab: sign-in and what it has loaded.
        function githubStatus(): string {
            const g = GitHubService
            return `signed in: ${g.authed ? g.login : "no"} · repos ${g.repos.length} · local ${g.local.length}`
                + ` · my PRs ${g.myPrs.length} · reviews ${g.reviewPrs.length} · issues ${g.issues.length}`
                + (g.remoteLoading || g.localLoading ? " · loading" : "")
        }
    }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { shell.closeOthers(cc); cc.toggle() }
        function open(): void { shell.closeOthers(cc); cc.show() }
        function close(): void { cc.close() }
        // wifi | bluetooth | ethernet | sound
        function page(name: string): void { shell.closeOthers(cc); cc.show(); cc.page = name }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { shell.closeOthers(notifs); notifs.toggle() }
        function open(): void { shell.closeOthers(notifs); notifs.show() }
        function close(): void { notifs.close() }
        function clear(): void { NotifService.clear() }
        // For scripts (gamemode hooks): "true" / "false".
        function dnd(): string { return NotifService.dnd ? "true" : "false" }
        function setDnd(on: bool): void { NotifService.dnd = on }
        function toggleDnd(): void { NotifService.dnd = !NotifService.dnd }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { shell.closeOthers(settings); settings.toggle() }
        function open(): void { shell.closeOthers(settings); settings.show() }
        function close(): void { settings.close() }
    }

    IpcHandler {
        target: "lyrics"
        function toggle(): void { lyrics.toggle() }
        function show(): void { lyrics.enabled = true }
        function hide(): void { lyrics.enabled = false }
        // Seconds added to the timing; positive shows lines later.
        function offset(seconds: real): void { LyricsService.offset = seconds }
        function reload(): void { LyricsService.reload() }
        // For checking what was found: "<source> · <n> lines · line <i> · <artist> - <title>".
        function status(): string {
            const state = LyricsService.loading ? "loading" : (LyricsService.source || "none")
            return `${state} · ${LyricsService.lines.length} lines · line ${LyricsService.currentIndex} · ${LyricsService.artist} - ${LyricsService.title}`
        }
    }

    IpcHandler {
        target: "clock"
        function toggle(): void { clock.toggle() }
        function show(): void { clock.enabled = true }
        function hide(): void { clock.enabled = false }
    }

    IpcHandler {
        target: "visualiser"
        function toggle(): void { visualiser.toggle() }
        function show(): void { visualiser.enabled = true }
        function hide(): void { visualiser.enabled = false }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { shell.closeOthers(walls); walls.toggle() }
        function open(): void { shell.closeOthers(walls); walls.show() }
        function close(): void { walls.cancel() }
        function apply(): void { walls.commit() }
        function next(): void { walls.step(1) }
        function prev(): void { walls.step(-1) }
    }

    IpcHandler {
        target: "wallhaven"
        function toggle(): void { shell.closeOthers(wallhaven); wallhaven.toggle() }
        function open(): void { shell.closeOthers(wallhaven); wallhaven.show() }
        function close(): void { wallhaven.close() }
        // Search with the saved filters, opening the panel.
        function search(query: string): void {
            shell.closeOthers(wallhaven)
            wallhaven.query = query
            wallhaven.show()
            wallhaven.search()
        }
        // For checking: "<state> · <shown>/<total> · page <n>/<last> · <sorting>".
        function status(): string {
            const w = wallhaven
            const state = w.error ? "error: " + w.error : w.loading ? "loading" : w.downloading ? "downloading" : "idle"
            return `${state} · ${w.results.count}/${w.total} · page ${w.page}/${w.lastPage} · ${w.sorting}`
        }
    }

    IpcHandler {
        target: "displays"
        function toggle(): void { shell.closeOthers(displays); displays.toggle() }
        function open(): void { shell.closeOthers(displays); displays.show() }
        function close(): void { displays.close() }
        // For checking: "<outputs with positions> · dirty/clean".
        function status(): string {
            const d = displays
            return d.outputs.map(o => `${o.name}@${d.layout[o.name].x},${d.layout[o.name].y}`).join(" ")
                + (d.dirty ? " · unapplied" : " · applied") + (d.message ? " · " + d.message : "")
        }
    }

    IpcHandler {
        target: "binds"
        function toggle(): void { shell.closeOthers(binds); binds.toggle() }
        function open(): void { shell.closeOthers(binds); binds.show() }
        function close(): void { binds.close() }
    }
}
