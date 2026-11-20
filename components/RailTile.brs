' RailTile — see RailTile.xml.
sub init()
    m.face = m.top.FindNode("railFace")
    m.glyph = m.top.FindNode("railGlyph")
    m.label = m.top.FindNode("railLabel")
    m.top.ObserveField("focused", "ApplyState")
    m.top.ObserveField("selected", "ApplyState")
end sub

sub SetTile(glyphUri as string, sectionName as string)
    m.glyph.uri = glyphUri
    m.label.text = sectionName
    ApplyState()
end sub

sub ApplyState()
    t = Theme()
    lit = m.top.focused = true or m.top.selected = true
    m.face.visible = m.top.focused = true
    if lit
        m.glyph.blendColor = t.accent
        m.glyph.opacity = 1.0
        m.label.color = t.accent
    else
        m.glyph.blendColor = "0xFFFFFFFF"
        m.glyph.opacity = 0.35
    end if
    m.label.visible = m.top.focused = true
end sub
