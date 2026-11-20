' PlayerOverlay — Stremio-style transport and menus over the Video node.
' See PlayerOverlay.xml for the remote map. Everything here acts on the Video
' node handed in through `video`; the only thing that leaves is `action`
' ({ type: "next" | "episode" | "prefetchNext", ... }) for PlayerScreen.

sub init()
    t = Theme()
    m.chrome = m.top.FindNode("chrome")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.subtitleLabel = m.top.FindNode("subtitleLabel")
    m.titleLabel.color = t.textWhite
    m.subtitleLabel.color = "0xFFFFFFB3"

    m.seekTrack = m.top.FindNode("seekTrack")
    m.seekFill = m.top.FindNode("seekFill")
    m.seekKnob = m.top.FindNode("seekKnob")
    m.scrubLabel = m.top.FindNode("scrubLabel")
    m.elapsedLabel = m.top.FindNode("elapsedLabel")
    m.durationLabel = m.top.FindNode("durationLabel")
    m.seekTrack.color = "0xFFFFFF40"
    m.top.FindNode("seekBuffered").color = "0xFFFFFF26"
    m.seekFill.color = t.accent
    m.scrubLabel.color = t.textWhite
    m.elapsedLabel.color = t.textWhite
    m.durationLabel.color = "0xFFFFFFB3"
    m.barWidth = 1728

    m.buttonRow = m.top.FindNode("buttonRow")

    m.nextPopup = m.top.FindNode("nextPopup")
    m.top.FindNode("nextBg").color = "0x101318EE"
    m.nextHeading = m.top.FindNode("nextHeading")
    m.nextTitle = m.top.FindNode("nextTitle")
    m.nextCountdown = m.top.FindNode("nextCountdown")
    m.nextPlayBg = m.top.FindNode("nextPlayBg")
    m.nextPlayLabel = m.top.FindNode("nextPlayLabel")
    m.nextDismissBg = m.top.FindNode("nextDismissBg")
    m.nextDismissLabel = m.top.FindNode("nextDismissLabel")
    m.nextHeading.color = t.accent
    m.nextTitle.color = t.textWhite
    m.nextCountdown.color = "0xFFFFFFB3"

    m.menu = m.top.FindNode("menu")
    m.top.FindNode("menuBg").color = "0x0D1013F5"
    m.menuTitle = m.top.FindNode("menuTitle")
    m.menuTitle.color = t.textWhite
    m.menuRowsGroup = m.top.FindNode("menuRows")
    m.menuRows = []
    for r = 0 to MENU_ROWS() - 1
        row = CreateObject("roSGNode", "Group")
        row.translation = [0, r * 70]
        bg = CreateObject("roSGNode", "Rectangle")
        bg.width = 504
        bg.height = 64
        bg.color = "0x00000000"
        label = CreateObject("roSGNode", "Label")
        label.translation = [24, 0]
        label.width = 400
        label.height = 64
        label.vertAlign = "center"
        label.font = "font:SmallSystemFont"
        check = CreateObject("roSGNode", "Poster")
        check.uri = "pkg:/images/player/check.png"
        check.width = 32
        check.height = 32
        check.translation = [452, 16]
        row.AppendChild(bg)
        row.AppendChild(label)
        row.AppendChild(check)
        m.menuRowsGroup.AppendChild(row)
        m.menuRows.Push({ group: row, bg: bg, label: label, check: check })
    end for
    m.menuLabels = []
    m.menuSel = 0
    m.menuChecked = -1
    m.menuTopRow = 0

    m.hideTimer = m.top.FindNode("hideTimer")
    m.hideTimer.ObserveField("fire", "onHideTimer")
    m.scrubTimer = m.top.FindNode("scrubTimer")
    m.scrubTimer.ObserveField("fire", "onScrubCommit")
    m.holdTimer = m.top.FindNode("holdTimer")
    m.holdTimer.ObserveField("fire", "onHoldTick")
    m.holdKey = ""
    m.holdDir = 0
    m.holdStart = 0
    m.holdStep = 0

    m.active = false
    m.row = "seek"
    m.btnIndex = 0
    m.buttons = []
    m.menuKind = ""
    m.menuValues = []
    m.scrubTarget = -1
    m.popupFocus = 0
    m.prefetchSent = false
    m.observedVideo = invalid
    RefreshLabels()
end sub

function MENU_ROWS() as integer
    return 12
end function

' One of the overlay's words, from the table PlayerScreen hands over.
function S(key as string) as string
    table = m.top.strings
    if table <> invalid
        value = table[key]
        if value <> invalid and value <> "" then return value
    end if
    return ""
end function

sub onStringsChanged()
    RefreshLabels()
end sub

sub RefreshLabels()
    m.nextHeading.text = UCase(S("nextEpisode"))
    m.nextPlayLabel.text = S("playNow")
    m.nextDismissLabel.text = S("dismiss")
end sub

' ---------------------------------------------------------------------------
' Lifecycle
' ---------------------------------------------------------------------------

' Called once the stream is actually playing: wire the video, build the buttons,
' take focus and flash the controls so the viewer sees they exist.
function Activate(params = invalid as dynamic) as void
    video = m.top.video
    if video = invalid then return
    if m.observedVideo = invalid or not m.observedVideo.IsSameNode(video)
        video.ObserveField("position", "onPosition")
        video.ObserveField("state", "onVideoState")
        m.observedVideo = video
    end if
    m.active = true
    RefreshLabels()
    BuildButtons()
    m.top.SetFocus(true)
    ShowChrome("seek")
end function

function Deactivate(params = invalid as dynamic) as void
    m.active = false
    CloseMenu(false)
    HideChrome()
    m.nextPopup.visible = false
    m.scrubTimer.control = "stop"
    m.holdTimer.control = "stop"
    m.holdKey = ""
    m.holdDir = 0
    m.holdStep = 0
    m.scrubTarget = -1
end function

' Per-play reset: a new episode starts with no pop-up history.
function ResetForPlay(params = invalid as dynamic) as void
    m.top.nextDismissed = false
    m.prefetchSent = false
    m.popupFocus = 0
    m.nextPopup.visible = false
    m.scrubTarget = -1
    m.seekFill.width = 0
    m.elapsedLabel.text = ""
    m.durationLabel.text = ""
end function

sub onTitleChanged()
    m.titleLabel.text = m.top.title
    m.subtitleLabel.text = m.top.subtitle
end sub

sub onNextInfoChanged()
    if m.active then BuildButtons()
end sub

sub onEpisodesChanged()
    if m.active then BuildButtons()
end sub

' ---------------------------------------------------------------------------
' Buttons
' ---------------------------------------------------------------------------

sub BuildButtons()
    keepId = ""
    if m.btnIndex >= 0 and m.btnIndex < m.buttons.Count() then keepId = m.buttons[m.btnIndex].id

    while m.buttonRow.GetChildCount() > 0
        m.buttonRow.RemoveChildIndex(0)
    end while
    m.buttons = []

    left = [{ id: "playPause", icon: PlayPauseIcon() }, { id: "back10", icon: "pkg:/images/player/back10.png" }, { id: "fwd10", icon: "pkg:/images/player/fwd10.png" }]
    if m.top.nextInfo <> invalid and m.top.nextInfo.Count() > 0 then left.Push({ id: "next", icon: "pkg:/images/player/next.png" })
    right = []
    if m.top.episodes <> invalid and m.top.episodes.Count() > 0 then right.Push({ id: "episodes", icon: "pkg:/images/player/episodes.png" })
    right.Push({ id: "subtitles", icon: "pkg:/images/player/subtitles.png" })
    right.Push({ id: "audio", icon: "pkg:/images/player/audio.png" })
    if SpeedSupported() then right.Push({ id: "speed", icon: "pkg:/images/player/speed.png" })

    x = 0
    for each b in left
        AddButton(b, x)
        x = x + 104
    end for
    x = m.barWidth - 88 - (right.Count() - 1) * 104
    for each b in right
        AddButton(b, x)
        x = x + 104
    end for

    m.btnIndex = 0
    for i = 0 to m.buttons.Count() - 1
        if m.buttons[i].id = keepId then m.btnIndex = i
    end for
    PaintFocus()
end sub

sub AddButton(b as object, x as integer)
    group = CreateObject("roSGNode", "Group")
    group.translation = [x, 0]
    ring = CreateObject("roSGNode", "Poster")
    ring.uri = "pkg:/images/player/knob.png"
    ring.width = 88
    ring.height = 88
    ring.opacity = 0
    icon = CreateObject("roSGNode", "Poster")
    icon.uri = b.icon
    icon.width = 48
    icon.height = 48
    icon.translation = [20, 20]
    group.AppendChild(ring)
    group.AppendChild(icon)
    m.buttonRow.AppendChild(group)
    m.buttons.Push({ id: b.id, ring: ring, icon: icon })
end sub

function PlayPauseIcon() as string
    video = m.top.video
    if video <> invalid and VideoStateIs("paused") then return "pkg:/images/player/play.png"
    return "pkg:/images/player/pause.png"
end function

sub PaintFocus()
    focusedSeek = m.chrome.visible and m.row = "seek" and m.menuKind = ""
    for i = 0 to m.buttons.Count() - 1
        b = m.buttons[i]
        if m.chrome.visible and m.row = "buttons" and i = m.btnIndex and m.menuKind = ""
            b.ring.opacity = 1
            b.ring.blendColor = Theme().accent
            b.icon.blendColor = Theme().onAccent
        else
            b.ring.opacity = 0
            b.icon.blendColor = "0xFFFFFFFF"
        end if
    end for
    if focusedSeek
        m.seekTrack.height = 10
        m.seekFill.height = 10
        m.seekTrack.translation = [0, -5]
        m.seekFill.translation = [0, -5]
        m.seekKnob.visible = true
    else
        m.seekTrack.height = 6
        m.seekFill.height = 6
        m.seekTrack.translation = [0, -3]
        m.seekFill.translation = [0, -3]
        m.seekKnob.visible = m.scrubTarget >= 0
    end if
end sub

sub ActivateButton(id as string)
    if id = "playPause"
        TogglePause()
    else if id = "back10"
        Scrub(-10)
    else if id = "fwd10"
        Scrub(10)
    else if id = "next"
        m.top.action = { type: "next" }
    else if id = "episodes" or id = "subtitles" or id = "audio" or id = "speed"
        OpenMenu(id)
    end if
end sub

' ---------------------------------------------------------------------------
' Chrome visibility
' ---------------------------------------------------------------------------

sub ShowChrome(row = "" as string)
    if not m.active then return
    if row <> "" then m.row = row
    m.chrome.visible = true
    UpdateBar()
    PaintFocus()
    ArmHide()
end sub

sub HideChrome()
    m.chrome.visible = false
    m.hideTimer.control = "stop"
    PaintFocus()
end sub

sub ArmHide()
    m.hideTimer.control = "stop"
    video = m.top.video
    if video <> invalid and VideoStateIs("paused") then return
    if m.menuKind <> "" then return
    m.hideTimer.control = "start"
end sub

sub onHideTimer()
    if m.menuKind <> "" or m.scrubTarget >= 0 then return
    video = m.top.video
    if video <> invalid and VideoStateIs("paused") then return
    HideChrome()
end sub

' ---------------------------------------------------------------------------
' Transport
' ---------------------------------------------------------------------------

sub TogglePause()
    video = m.top.video
    if video = invalid then return
    if VideoStateIs("playing") or VideoStateIs("buffering")
        video.control = "pause"
    else if VideoStateIs("paused")
        video.control = "resume"
    end if
end sub

' Skips accumulate: each press moves the target, and the seek is issued once
' the presses stop (scrubTimer), so five quick Rights are one +50s seek rather
' than five re-buffers.
sub Scrub(delta as integer)
    video = m.top.video
    if video = invalid then return
    duration = CurDur()
    base = m.scrubTarget
    if base < 0 then base = CurPos()
    target = base + delta
    if target < 0 then target = 0
    if duration > 0 and target > duration - 2 then target = duration - 2
    m.scrubTarget = target
    m.scrubTimer.control = "stop"
    m.scrubTimer.control = "start"
    ShowChrome()
end sub

' ---------------------------------------------------------------------------
' Progressive (accelerated) scrubbing.
'
' A tap moves 10s (30s for Rew/FF). Holding the key keeps moving the target on
' every holdTimer tick, and the step grows with how long the key has been held:
'   0.0-0.5s  nothing extra (a tap stays a tap)
'   0.5-1.5s  10s per tick   »
'   1.5-3.0s  30s per tick   »»
'   3.0-5.0s  60s per tick   »»»
'   5.0s+     ~2.5% of the video per tick (2-5 min)   »»»»
' The seek itself is issued once, after the key is released (scrubTimer), so a
' long hold is one re-buffer, not dozens.
' ---------------------------------------------------------------------------

sub BeginHold(key as string, dir as integer, tapStep as integer)
    if m.holdKey = key then return ' a repeated press while held: already ticking
    m.holdKey = key
    m.holdDir = dir
    m.holdStart = UpTime(0)
    m.holdStep = 0
    Scrub(dir * tapStep)
    m.holdTimer.control = "stop"
    m.holdTimer.control = "start"
end sub

sub EndHold()
    m.holdTimer.control = "stop"
    m.holdKey = ""
    m.holdDir = 0
    m.holdStep = 0
    ' Commit shortly after release: snappier than the idle tap delay.
    if m.scrubTarget >= 0
        m.scrubTimer.control = "stop"
        m.scrubTimer.control = "start"
    end if
    UpdateBar()
end sub

function HoldStepFor(elapsed as float) as integer
    if elapsed < 0.5 then return 0
    if elapsed < 1.5 then return 10
    if elapsed < 3.0 then return 30
    if elapsed < 5.0 then return 60
    big = Int(CurDur() * 0.025)
    if big < 120 then big = 120
    if big > 300 then big = 300
    return big
end function

sub onHoldTick()
    if m.holdKey = "" or not m.active
        m.holdTimer.control = "stop"
        return
    end if
    elapsed = UpTime(0) - m.holdStart
    ' A release the overlay never heard (focus moved, remote dropped) must not
    ' scrub forever.
    if elapsed > 30
        EndHold()
        return
    end if
    m.holdStep = HoldStepFor(elapsed)
    if m.holdStep <= 0 then return
    Scrub(m.holdDir * m.holdStep)
end sub

' Chevrons for the current hold speed ("»» " / "«« "), empty for a plain tap.
function ScrubRateText() as string
    if m.holdKey = "" or m.holdStep <= 0 then return ""
    level = 1
    if m.holdStep >= 30 then level = 2
    if m.holdStep >= 60 then level = 3
    if m.holdStep >= 120 then level = 4
    glyph = "»"
    if m.holdDir < 0 then glyph = "«"
    text = ""
    for i = 1 to level
        text = text + glyph
    end for
    return text + "  "
end function

sub onScrubCommit()
    if m.scrubTarget < 0 then return
    ' Never seek mid-hold: the release (EndHold) re-arms the commit.
    if m.holdKey <> "" then return
    video = m.top.video
    target = m.scrubTarget
    m.scrubTarget = -1
    if video <> invalid then video.seek = target
    UpdateBar()
    PaintFocus()
    ArmHide()
end sub

' State of the Video node as a plain string ("" when there is none).
function VideoStateIs(name as string) as boolean
    video = m.top.video
    if video = invalid then return false
    state = video.state
    if state = invalid then return false
    return state = name
end function

function CaptionModeText(video as object) as string
    if video = invalid or not video.HasField("globalCaptionMode") then return ""
    mode = video.globalCaptionMode
    if mode = invalid then return ""
    return mode
end function

function CurPos() as float
    video = m.top.video
    if video = invalid or video.position = invalid then return 0
    return video.position
end function

function CurDur() as float
    video = m.top.video
    if video = invalid or video.duration = invalid then return 0
    return video.duration
end function

sub onPosition()
    if not m.active then return
    if m.chrome.visible then UpdateBar()
    CheckNextPopup()
end sub

sub onVideoState()
    if not m.active then return
    video = m.top.video
    if video = invalid then return
    for each b in m.buttons
        if b.id = "playPause" then b.icon.uri = PlayPauseIcon()
    end for
    if VideoStateIs("paused")
        ShowChrome()
    else if VideoStateIs("playing") and m.chrome.visible
        ArmHide()
    end if
end sub

sub UpdateBar()
    duration = CurDur()
    position = CurPos()
    shown = position
    if m.scrubTarget >= 0 then shown = m.scrubTarget
    ratio = 0.0
    if duration > 0 then ratio = shown / duration
    if ratio < 0 then ratio = 0
    if ratio > 1 then ratio = 1
    m.seekFill.width = Int(m.barWidth * ratio)
    knobX = Int(m.barWidth * ratio)
    m.seekKnob.translation = [knobX - 14, -14]
    m.scrubLabel.translation = [knobX - 100, -64]
    m.scrubLabel.visible = m.scrubTarget >= 0
    m.scrubLabel.text = ScrubRateText() + ClockText(shown)
    m.elapsedLabel.text = ClockText(shown)
    if duration > 0
        m.durationLabel.text = ClockText(duration)
    else
        m.durationLabel.text = ""
    end if
end sub

function ClockText(seconds as float) as string
    total = Int(seconds)
    if total < 0 then total = 0
    h = Int(total / 3600)
    mm = Int((total - h * 3600) / 60)
    sec = total - h * 3600 - mm * 60
    ss = sec.ToStr()
    if sec < 10 then ss = "0" + ss
    if h > 0
        ms = mm.ToStr()
        if mm < 10 then ms = "0" + ms
        return h.ToStr() + ":" + ms + ":" + ss
    end if
    return mm.ToStr() + ":" + ss
end function

' ---------------------------------------------------------------------------
' Up next
' ---------------------------------------------------------------------------

function NEXT_POPUP_SECONDS() as integer
    return 30
end function

sub CheckNextPopup()
    info = m.top.nextInfo
    if info = invalid or info.Count() = 0 then return
    duration = CurDur()
    if duration < 120 then return
    remaining = duration - CurPos()
    if remaining <= 90 and not m.prefetchSent
        m.prefetchSent = true
        m.top.action = { type: "prefetchNext" }
    end if
    video = m.top.video
    show = remaining <= NEXT_POPUP_SECONDS() and remaining > 0 and not m.top.nextDismissed and VideoStateIs("playing")
    if show
        if not m.nextPopup.visible then m.popupFocus = 0
        m.nextTitle.text = info.label
        secs = Int(remaining)
        if secs < 0 then secs = 0
        m.nextCountdown.text = Fill(S("nextIn"), { seconds: secs.ToStr() })
        m.nextPopup.visible = true
        PaintPopup()
    else if m.nextPopup.visible and (m.top.nextDismissed or remaining > NEXT_POPUP_SECONDS())
        m.nextPopup.visible = false
    end if
end sub

sub PaintPopup()
    accent = Theme().accent
    if m.popupFocus = 0
        m.nextPlayBg.color = accent
        m.nextPlayLabel.color = Theme().onAccent
        m.nextDismissBg.color = "0xFFFFFF1F"
        m.nextDismissLabel.color = "0xFFFFFFFF"
    else
        m.nextPlayBg.color = "0xFFFFFF1F"
        m.nextPlayLabel.color = "0xFFFFFFFF"
        m.nextDismissBg.color = accent
        m.nextDismissLabel.color = Theme().onAccent
    end if
end sub

function PopupHasFocus() as boolean
    return m.nextPopup.visible and not m.chrome.visible and m.menuKind = ""
end function

' ---------------------------------------------------------------------------
' Menus
' ---------------------------------------------------------------------------

function SpeedSupported() as boolean
    video = m.top.video
    return video <> invalid and video.HasField("playbackSpeed")
end function

function SpeedValues() as object
    return [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
end function

sub OpenMenu(kind as string)
    video = m.top.video
    if video = invalid then return
    labels = []
    values = []
    selected = 0
    if kind = "subtitles"
        m.menuTitle.text = S("subtitles")
        labels.Push(S("off"))
        values.Push("")
        captionsOn = true
        if CaptionModeText(video) = "Off" then captionsOn = false
        current = ""
        if video.HasField("currentSubtitleTrack") and video.currentSubtitleTrack <> invalid then current = video.currentSubtitleTrack
        tracks = video.availableSubtitleTracks
        if tracks <> invalid
            for each tr in tracks
                name = tr.TrackName
                if name = invalid then continue for
                label = tr.Description
                if label = invalid or label = "" then label = tr.Language
                if label = invalid or label = "" then label = S("captionsFallback")
                labels.Push(label)
                values.Push(name)
                if captionsOn and name = current then selected = labels.Count() - 1
            end for
        end if
    else if kind = "audio"
        m.menuTitle.text = S("audio")
        current = ""
        if video.currentAudioTrack <> invalid then current = video.currentAudioTrack
        tracks = video.availableAudioTracks
        if tracks <> invalid
            for each tr in tracks
                if tr.Track = invalid then continue for
                label = tr.Name
                if label = invalid or label = "" then label = tr.Language
                if label = invalid or label = "" then label = S("audio") + " " + (labels.Count() + 1).ToStr()
                if tr.Format <> invalid and tr.Format <> "" then label = label + "  ·  " + UCase(tr.Format)
                labels.Push(label)
                values.Push(tr.Track)
                if tr.Track = current then selected = labels.Count() - 1
            end for
        end if
        if labels.Count() = 0
            labels.Push(S("audioDefault"))
            values.Push("")
        end if
    else if kind = "speed"
        m.menuTitle.text = S("speed")
        currentSpeed = 1.0
        if video.playbackSpeed <> invalid then currentSpeed = video.playbackSpeed
        for each v in SpeedValues()
            labels.Push(Fill(S("speedValue"), { value: SpeedText(v) }))
            values.Push(v)
            if Abs(v - currentSpeed) < 0.01 then selected = labels.Count() - 1
        end for
    else if kind = "episodes"
        m.menuTitle.text = S("episodes")
        eps = m.top.episodes
        if eps <> invalid
            for i = 0 to eps.Count() - 1
                labels.Push(eps[i].label)
                values.Push(i)
            end for
        end if
        if m.top.episodeIndex >= 0 then selected = m.top.episodeIndex
    end if
    if labels.Count() = 0 then return

    if selected >= labels.Count() then selected = 0
    m.menuKind = kind
    m.menuValues = values
    m.menuLabels = labels
    m.menuChecked = selected
    m.menuSel = selected
    m.menuTopRow = 0
    m.menu.visible = true
    m.hideTimer.control = "stop"
    PaintMenu()
    PaintFocus()
end sub

' Paint the visible window of the menu around the selection.
sub PaintMenu()
    count = m.menuLabels.Count()
    rows = MENU_ROWS()
    if m.menuSel < m.menuTopRow then m.menuTopRow = m.menuSel
    if m.menuSel >= m.menuTopRow + rows then m.menuTopRow = m.menuSel - rows + 1
    if m.menuTopRow < 0 then m.menuTopRow = 0
    accent = Theme().accent
    for r = 0 to rows - 1
        row = m.menuRows[r]
        idx = m.menuTopRow + r
        if idx < count
            row.group.visible = true
            row.label.text = m.menuLabels[idx]
            row.check.visible = idx = m.menuChecked
            if idx = m.menuSel
                row.bg.color = accent
                row.label.color = Theme().onAccent
                row.check.blendColor = Theme().onAccent
            else
                row.bg.color = "0x00000000"
                row.label.color = "0xFFFFFFE6"
                row.check.blendColor = accent
            end if
        else
            row.group.visible = false
        end if
    end for
end sub

function SpeedText(v as float) as string
    text = Str(v).Trim()
    if Left(text, 1) = "." then text = "0" + text
    return text
end function

sub onMenuItemSelected()
    index = m.menuSel
    kind = m.menuKind
    if index < 0 or index >= m.menuValues.Count() then return
    value = m.menuValues[index]
    video = m.top.video
    if video <> invalid
        if kind = "subtitles"
            if value = ""
                if video.HasField("globalCaptionMode") then video.globalCaptionMode = "Off"
            else
                if video.HasField("globalCaptionMode") then video.globalCaptionMode = "On"
                if video.HasField("subtitleTrack") then video.subtitleTrack = value
            end if
        else if kind = "audio"
            if value <> "" then video.audioTrack = value
        else if kind = "speed"
            if video.HasField("playbackSpeed") then video.playbackSpeed = value
        else if kind = "episodes"
            if value <> m.top.episodeIndex then m.top.action = { type: "episode", index: value }
        end if
    end if
    CloseMenu(true)
end sub

sub CloseMenu(showControls as boolean)
    if m.menuKind = "" then return
    m.menuKind = ""
    m.menu.visible = false
    m.menuLabels = []
    if m.active then m.top.SetFocus(true)
    if showControls then ShowChrome("buttons") else PaintFocus()
end sub

' ---------------------------------------------------------------------------
' Keys
' ---------------------------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        if m.holdKey <> "" and key = m.holdKey
            EndHold()
            return true
        end if
        return false
    end if
    if not m.active then return false

    if m.menuKind <> ""
        if key = "back" or key = "left"
            CloseMenu(true)
        else if key = "up"
            if m.menuSel > 0 then m.menuSel = m.menuSel - 1
            PaintMenu()
        else if key = "down"
            if m.menuSel < m.menuLabels.Count() - 1 then m.menuSel = m.menuSel + 1
            PaintMenu()
        else if key = "OK"
            onMenuItemSelected()
        else if key = "options"
            CloseMenu(true)
        end if
        ' Everything else is swallowed so nothing leaks to the video.
        return true
    end if

    if key = "back" then return false

    if key = "options"
        OpenMenu("subtitles")
        return true
    end if
    if key = "play"
        TogglePause()
        ShowChrome()
        return true
    end if
    if key = "replay"
        Scrub(-10)
        return true
    end if
    if key = "rewind"
        m.row = "seek"
        BeginHold(key, -1, 30)
        return true
    end if
    if key = "fastforward"
        m.row = "seek"
        BeginHold(key, 1, 30)
        return true
    end if

    if PopupHasFocus()
        if key = "left" or key = "right"
            m.popupFocus = 1 - m.popupFocus
            PaintPopup()
            return true
        else if key = "OK"
            if m.popupFocus = 0
                m.nextPopup.visible = false
                m.top.action = { type: "next" }
            else
                m.top.nextDismissed = true
                m.nextPopup.visible = false
            end if
            return true
        end if
    end if

    if not m.chrome.visible
        if key = "OK"
            TogglePause()
            ShowChrome("seek")
        else if key = "left"
            m.row = "seek"
            BeginHold(key, -1, 10)
        else if key = "right"
            m.row = "seek"
            BeginHold(key, 1, 10)
        else if key = "up" or key = "down"
            ShowChrome("buttons")
        end if
        return true
    end if

    ' Controls are up.
    ArmHide()
    if m.row = "seek"
        if key = "left"
            BeginHold(key, -1, 10)
        else if key = "right"
            BeginHold(key, 1, 10)
        else if key = "OK"
            if m.scrubTarget >= 0
                m.scrubTimer.control = "stop"
                onScrubCommit()
            else
                TogglePause()
            end if
        else if key = "down"
            m.row = "buttons"
            PaintFocus()
        else if key = "up"
            HideChrome()
        end if
        return true
    end if

    ' Button row
    if key = "left"
        if m.btnIndex > 0 then m.btnIndex = m.btnIndex - 1
        PaintFocus()
    else if key = "right"
        if m.btnIndex < m.buttons.Count() - 1 then m.btnIndex = m.btnIndex + 1
        PaintFocus()
    else if key = "up"
        m.row = "seek"
        PaintFocus()
    else if key = "down"
        HideChrome()
    else if key = "OK"
        if m.btnIndex >= 0 and m.btnIndex < m.buttons.Count() then ActivateButton(m.buttons[m.btnIndex].id)
    end if
    return true
end function
