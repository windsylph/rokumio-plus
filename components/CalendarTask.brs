' CalendarTask — see CalendarTask.xml. A series whose meta cannot be fetched is
' skipped rather than failing the whole calendar.
sub init()
    m.top.functionName = "load"
end sub

sub load()
    entries = []
    try
        http = Transport()
        store = EpisodesStore(http)
        fromDate = m.top.fromDate
        toDate = m.top.toDate
        for each item in m.top.series
            if item = invalid or item.metaId = invalid then continue for
            ' One retry: a single slow answer must not drop a whole series
            ' from the calendar.
            answer = invalid
            for attempt = 1 to 2
                try
                    answer = store.GetMeta(m.top.addonAddress, "series", item.metaId)
                catch fetchError
                    answer = invalid
                end try
                if answer <> invalid and answer.ok = true and answer.meta <> invalid then exit for
            end for
            if answer = invalid or answer.ok <> true or answer.meta = invalid then continue for
            meta = answer.meta
            if meta.videos = invalid or GetInterface(meta.videos, "ifArray") = invalid then continue for
            seriesName = item.name
            if seriesName = invalid or seriesName = "" then seriesName = meta.name
            poster = item.poster
            if (poster = invalid or poster = "") and meta.poster <> invalid then poster = meta.poster
            background = ""
            if meta.background <> invalid and GetInterface(meta.background, "ifString") <> invalid then background = meta.background
            for each video in meta.videos
                if video = invalid then continue for
                released = video.released
                if released = invalid or GetInterface(released, "ifString") = invalid then continue for
                if Len(released) < 10 then continue for
                day = Left(released, 10)
                if day < fromDate or day > toDate then continue for
                season = video.season
                if season = invalid or season = 0 then continue for
                number = video.episode
                if number = invalid then number = video.number
                if number = invalid then continue for
                title = video.name
                if title = invalid then title = video.title
                if title = invalid then title = ""
                entries.Push({
                    date: day
                    metaId: item.metaId
                    seriesName: seriesName
                    poster: poster
                    background: background
                    season: season
                    episode: number
                    title: title
                })
            end for
        end for
        entries.SortBy("date")
        m.top.result = { ok: true, entries: entries }
    catch e
        m.top.result = { ok: false, entries: entries, error: e.message }
    end try
end sub
