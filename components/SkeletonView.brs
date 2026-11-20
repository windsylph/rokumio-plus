' SkeletonView — see SkeletonView.xml.

sub init()
    m.shapes = m.top.FindNode("shapes")
    m.pulse = m.top.FindNode("pulse")
    m.top.visible = false
end sub

sub onActiveChanged()
    if m.top.active
        m.top.visible = true
        m.shapes.opacity = 1.0
        m.pulse.control = "start"
    else
        m.pulse.control = "stop"
        m.top.visible = false
    end if
end sub

function Ghost(x as integer, y as integer, w as integer, h as integer, alpha as string) as object
    p = CreateObject("roSGNode", "Poster")
    p.uri = "pkg:/images/ui/card_sm.9.png"
    p.translation = [x, y]
    p.width = w
    p.height = h
    p.blendColor = "0xFFFFFF" + alpha
    m.shapes.AppendChild(p)
    return p
end function

function Num(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    return Int(value)
end function

sub onLayoutChanged()
    while m.shapes.GetChildCount() > 0
        m.shapes.RemoveChildIndex(0)
    end while
    l = m.top.layout
    if l = invalid then return
    kind = "grid"
    if l.kind <> invalid then kind = l.kind
    ' "bars": free-placed text ghosts [{ x, y, w, h }] (e.g. a details block).
    if kind = "bars"
        if l.bars <> invalid
            for each b in l.bars
                Ghost(Num(b.x, 0), Num(b.y, 0), Num(b.w, 200), Num(b.h, 20), "17")
            end for
        end if
        return
    end if
    x0 = Num(l.x, 0)
    y0 = Num(l.y, 0)
    rows = Num(l.rows, 2)
    cols = Num(l.cols, 6)
    tw = Num(l.tileW, 270)
    th = Num(l.tileH, 405)
    gx = Num(l.gapX, 18)
    gy = Num(l.gapY, 40)
    captions = l.captions = true

    y = y0
    for r = 0 to rows - 1
        if kind = "rows"
            ' Row title bar, as wide as a typical "Popular · Movies".
            Ghost(x0, y, 260, 30, "1F")
            y = y + 50
        end if
        if kind = "cards"
            ' One wide card per row with a thumbnail block and three text lines.
            Ghost(x0, y, tw, th, "12")
            pad = 24
            thumb = 0
            if l.thumbW <> invalid
                thumb = Int(l.thumbW)
                Ghost(x0 + pad, y + pad, thumb, th - 2 * pad, "14")
                thumb = thumb + pad
            end if
            tx = x0 + pad + thumb
            Ghost(tx, y + pad + 6, Int((tw - thumb - 2 * pad) * 0.45), 28, "1F")
            Ghost(tx, y + pad + 56, Int((tw - thumb - 2 * pad) * 0.8), 18, "14")
            Ghost(tx, y + pad + 86, Int((tw - thumb - 2 * pad) * 0.6), 18, "14")
            y = y + th + gy
        else
            for c = 0 to cols - 1
                x = x0 + c * (tw + gx)
                Ghost(x, y, tw, th, "12")
                if captions then Ghost(x + Int(tw * 0.2), y + th + 16, Int(tw * 0.6), 18, "14")
            end for
            y = y + th + gy
            if captions then y = y + 48
        end if
    end for

    if l.panel <> invalid
        p = l.panel
        px = Num(p.x, 1296)
        py = Num(p.y, 60)
        pw = Num(p.w, 564)
        ph = Num(p.h, 980)
        Ghost(px, py, pw, ph, "0D")
        Ghost(px + 14, py + 14, pw - 28, Int((pw - 28) * 9 / 16), "14")
        ty = py + 14 + Int((pw - 28) * 9 / 16) + 30
        Ghost(px + 32, ty, Int(pw * 0.55), 36, "1F")
        Ghost(px + 32, ty + 60, Int(pw * 0.4), 20, "14")
        for i = 0 to 3
            Ghost(px + 32, ty + 110 + i * 34, Int((pw - 64) * (0.95 - i * 0.12)), 18, "14")
        end for
    end if
end sub
