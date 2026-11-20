' CalendarScreen — see CalendarScreen.xml.
'
' Window: seven days back (what just aired) to thirty days ahead. Rows are days
' in date order; the first row at or after today takes focus so the screen
' opens on "what's next" rather than on last week.

sub init()
    m.hero = m.top.FindNode("hero")
    m.heading = m.top.FindNode("calendarHeading")
    m.grid = m.top.FindNode("calendarGrid")
    m.status = m.top.FindNode("calendarStatus")
    t = Theme()
    m.heading.color = t.textPrimary
    m.status.color = t.textSecondary
    m.grid.focusBitmapBlendColor = t.accentFocus
    m.grid.rowLabelColor = t.accent
    m.grid.ObserveField("rowItemFocused", "onFocused")
    m.grid.ObserveField("rowItemSelected", "onSelected")
    m.tasks = []
    m.pending = 0
    m.loaded = []
    m.loadKey = ""
    ' Last schedule built, reused for 15 minutes while the Library is unchanged
    ' so reopening the Calendar is instant and costs no requests.
    m.cache = invalid
    m.days = []
    m.cinemetaAddress = ""
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    m.heading.text = Lang("calendar", "title")
    ' Back from Details re-enters with invalid params: keep the schedule and
    ' the focused tile instead of refetching every series.
    if params = invalid
        if m.tasks.Count() > 0 then return
        if m.days.Count() > 0
            m.grid.SetFocus(true)
            return
        end if
    end if
    m.cinemetaAddress = CinemetaAddress()
    Load()
end function

function OnExit() as void
    CancelTask()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

function CinemetaAddress() as string
    if m.stores <> invalid
        addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
        if addon <> invalid and addon.address <> invalid then return addon.address
    end if
    return "https://v3-cinemeta.strem.io"
end function

sub CancelTask()
    for each task in m.tasks
        AsyncTask_Reap(task, m.top, true)
    end for
    m.tasks = []
    m.pending = 0
end sub

function CALENDAR_BATCHES() as integer
    return 4
end function

function CALENDAR_CACHE_SECONDS() as integer
    return 900
end function

' yyyy-mm-dd for today + offsetDays, in the device's local time.
function IsoDay(offsetDays as integer) as string
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    dt.FromSeconds(dt.AsSeconds() + offsetDays * 86400)
    return Left(dt.ToISOString(), 10)
end function

sub Load()
    CancelTask()
    series = []
    if m.stores <> invalid
        items = m.stores.library.callFunc("LibraryLibraryView", "series", "recent")
        if items <> invalid
            for each item in items
                if item.metaId = invalid then continue for
                series.Push({ metaId: item.metaId, name: item.name, poster: item.poster })
                ' Bounded: one request per series, and a library can be large.
                if series.Count() >= 60 then exit for
            end for
        end if
    end if
    if series.Count() = 0
        ShowEmpty(Lang("calendar", "emptyLibrary"))
        return
    end if
    m.today = IsoDay(0)
    key = m.today
    for each item in series
        key = key + "|" + StringOf(item.metaId)
    end for
    if m.cache <> invalid and m.cache.key = key and UpTime(0) - m.cache.at < CALENDAR_CACHE_SECONDS()
        RenderSchedule(m.cache.entries)
        return
    end if
    m.loadKey = key
    m.status.text = Lang("calendar", "loading")
    m.status.visible = true

    ' Parallel batches: each task walks its own slice of the series, so a
    ' 40-series library costs ~10 sequential requests instead of 40.
    batches = CALENDAR_BATCHES()
    if series.Count() < batches then batches = series.Count()
    slices = []
    for b = 0 to batches - 1
        slices.Push([])
    end for
    for i = 0 to series.Count() - 1
        slices[i MOD batches].Push(series[i])
    end for
    m.loaded = []
    m.pending = batches
    fromDate = IsoDay(-7)
    toDate = IsoDay(30)
    for b = 0 to batches - 1
        task = AsyncTask_Launch(m.top, "CalendarTask", "onLoaded", {
            addonAddress: m.cinemetaAddress
            series: slices[b]
            fromDate: fromDate
            toDate: toDate
        }, "calendarLoader" + b.ToStr())
        if task <> invalid
            m.tasks.Push(task)
        else
            m.pending = m.pending - 1
        end if
    end for
    if m.pending <= 0 then RenderSchedule([])
end sub

sub ShowEmpty(text as string)
    m.days = []
    m.grid.content = CreateObject("roSGNode", "ContentNode")
    m.grid.visible = false
    m.status.text = text
    m.status.visible = true
    if m.hero <> invalid
        m.hero.callFunc("Clear")
        m.hero.visible = false
    end if
    if m.top.screenActive then m.top.SetFocus(true)
end sub

sub onLoaded(event as object)
    task = event.getRoSGNode()
    if task = invalid then return
    ' Only tasks this load launched count; a reaped one cannot report.
    idx = -1
    for i = 0 to m.tasks.Count() - 1
        if m.tasks[i].IsSameNode(task) then idx = i
    end for
    if idx < 0 then return
    m.tasks.Delete(idx)
    result = task.result
    AsyncTask_Reap(task, m.top, false)
    if result <> invalid and result.entries <> invalid
        for each e in result.entries
            m.loaded.Push(e)
        end for
    end if
    m.pending = m.pending - 1
    if m.pending > 0 then return

    entries = m.loaded
    m.loaded = []
    entries.SortBy("date")
    m.cache = { key: m.loadKey, entries: entries, at: UpTime(0) }
    RenderSchedule(entries)
end sub

sub RenderSchedule(entries as object)
    if entries.Count() = 0
        ShowEmpty(Lang("calendar", "nothingScheduled"))
        return
    end if

    ' Group into days (entries arrive sorted by date).
    days = []
    for each e in entries
        if days.Count() = 0 or days[days.Count() - 1].date <> e.date
            days.Push({ date: e.date, entries: [] })
        end if
        days[days.Count() - 1].entries.Push(e)
    end for
    m.days = days

    content = CreateObject("roSGNode", "ContentNode")
    focusRow = days.Count() - 1
    for d = 0 to days.Count() - 1
        day = days[d]
        row = content.CreateChild("ContentNode")
        row.title = DayLabel(day.date)
        for each e in day.entries
            tile = row.CreateChild("TileContent")
            tile.title = StringOf(e.seriesName) + "  ·  " + EpisodeMarker(e.season, e.episode)
            if e.poster <> invalid and e.poster <> "" then tile.hdPosterUrl = e.poster
        end for
    end for
    ' The first day on or after today; if everything already aired, the last.
    for d = 0 to days.Count() - 1
        if days[d].date >= m.today
            focusRow = d
            exit for
        end if
    end for

    m.status.visible = false
    m.grid.visible = true
    if m.hero <> invalid then m.hero.visible = true
    m.grid.content = content
    m.grid.jumpToRowItem = [focusRow, 0]
    ' The fetch can land while Details is on top of us; never steal its focus.
    if m.top.screenActive then m.grid.SetFocus(true)
    RenderHero(focusRow, 0)
end sub

function EpisodeMarker(season as dynamic, episode as dynamic) as string
    return Fill(Lang("common", "episodeMarker"), { season: StringOf(season), episode: StringOf(episode) })
end function

' "Today · Nov 18", "Tomorrow · Nov 19", "Yesterday · Nov 17", "Nov 25".
function DayLabel(iso as string) as string
    months = LangList("common", "months")
    month = Val(Mid(iso, 6, 2))
    dayNum = Val(Mid(iso, 9, 2))
    monthName = Mid(iso, 6, 2)
    if months <> invalid and month >= 1 and month <= months.Count() then monthName = months[month - 1]
    ' Short on purpose: the RowList clips a row label to the first tile's width.
    if iso = m.today then return Lang("calendar", "today")
    if iso = IsoDay(1) then return Lang("calendar", "tomorrow")
    if iso = IsoDay(-1) then return Lang("calendar", "yesterday")
    return Fill(Lang("calendar", "dayDate"), { month: monthName, day: dayNum.ToStr() })
end function

' "Tomorrow · Nov 20" for the preview card, which has the room.
function FullDayLabel(iso as string) as string
    short = DayLabel(iso)
    months = LangList("common", "months")
    month = Val(Mid(iso, 6, 2))
    monthName = Mid(iso, 6, 2)
    if months <> invalid and month >= 1 and month <= months.Count() then monthName = months[month - 1]
    dated = Fill(Lang("calendar", "dayDate"), { month: monthName, day: Val(Mid(iso, 9, 2)).ToStr() })
    if short = dated then return dated
    return short + "  ·  " + dated
end function

function EntryAt(rowIndex as integer, itemIndex as integer) as dynamic
    if rowIndex < 0 or rowIndex >= m.days.Count() then return invalid
    list = m.days[rowIndex].entries
    if itemIndex < 0 or itemIndex >= list.Count() then return invalid
    return list[itemIndex]
end function

sub onFocused()
    data = m.grid.rowItemFocused
    if data = invalid or data.Count() < 2 then return
    RenderHero(data[0], data[1])
end sub

sub RenderHero(rowIndex as integer, itemIndex as integer)
    e = EntryAt(rowIndex, itemIndex)
    if e = invalid or m.hero = invalid then return
    line = EpisodeMarker(e.season, e.episode)
    if e.title <> invalid and e.title <> "" then line = line + "  ·  " + StringOf(e.title)
    line = line + "  —  " + FullDayLabel(e.date)
    ' The card's art slot is landscape: hand it the series backdrop so the
    ' portrait poster is never zoom-cropped into it.
    m.hero.callFunc("Render", {
        name: e.seriesName
        title: e.seriesName
        poster: e.poster
        background: e.background
        type: "series"
        description: line
    })
end sub

sub onSelected()
    data = m.grid.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    e = EntryAt(data[0], data[1])
    if e = invalid then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.cinemetaAddress
            heroTextureReady: false
            meta: {
                id: e.metaId
                type: "series"
                name: e.seriesName
                poster: e.poster
            }
        }
    }
end sub
