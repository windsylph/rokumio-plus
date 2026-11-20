' AddonCard — rich add-on card for the Add-ons screen.
' Scalable 9-patch frame (1400x320) with logo, metadata, description, and action.

sub init()
    m.border = m.top.FindNode("tileBorder")
    m.face = m.top.FindNode("tileFace")
    m.logoBg = m.top.FindNode("logoBg")
    m.logo = m.top.FindNode("addonLogo")
    m.name = m.top.FindNode("addonName")
    m.version = m.top.FindNode("addonVersion")
    m.scope = m.top.FindNode("addonScope")
    m.description = m.top.FindNode("addonDescription")
    m.action = m.top.FindNode("addonAction")
    m.isPlaceholder = true

    t = Theme()
    m.name.color = t.textPrimary
    m.version.color = t.textSecondary
    m.scope.color = t.textSecondary
    m.description.color = t.textSecondary
    m.action.color = t.textSecondary
    if m.logoBg <> invalid then m.logoBg.opacity = 0
    m.logo.blendColor = "0xFFFFFFFF"

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onFocusChanged")
    m.top.ObserveField("rowHasFocus", "onFocusChanged")
    m.logo.ObserveField("loadStatus", "onLogoLoadStatus")
    UpdateLook()
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    for each field in ["title", "description", "addonLogo", "addonVersion", "addonScope", "actionLabel", "actionKey"]
        content.ObserveField(field, "onContentChanged")
    end for
    ApplyContent()
end sub

sub onContentChanged()
    ApplyContent()
end sub

function IsPlaceholderLogo(uri as dynamic) as boolean
    value = StringOf(uri).Trim()
    if value = "" then return true
    if value = "pkg:/images/puzzle.png" then return true
    if value.InStr("puzzle.png") >= 0 then return true
    return false
end function

sub ApplyContent()
    content = m.top.itemContent
    if content = invalid then return
    m.name.text = StringOf(content.title)
    m.version.text = StringOf(content.addonVersion)
    m.scope.text = StringOf(content.addonScope)
    m.description.text = StringOf(content.description)
    m.action.text = StringOf(content.actionLabel)

    rawLogo = ""
    if content.addonLogo <> invalid then rawLogo = StringOf(content.addonLogo).Trim()
    m.isPlaceholder = IsPlaceholderLogo(rawLogo)
    uri = RokuLogoUri(rawLogo)
    if StringOf(m.logo.uri) <> uri
        ResetLogoBox()
        m.logo.uri = uri
    end if
    ' A recycled card can be handed the image it already holds: no reload, so
    ' no "ready" event — fit from the bitmap that is already there.
    if m.logo.loadStatus = "ready" then FitImageToBox(m.logo, 52, 88, 144, 144, "center", "center")
    UpdateLook()
end sub

' The icon's box (144x144 at [52, 88]); a fresh load starts from it.
sub ResetLogoBox()
    m.logo.width = 144
    m.logo.height = 144
    m.logo.translation = [52, 88]
end sub

sub onLogoLoadStatus()
    status = ""
    if m.logo <> invalid then status = m.logo.loadStatus
    if status = "failed"
        m.isPlaceholder = true
        ResetLogoBox()
        UpdateLook()
    else if status = "ready"
        ' Keep the add-on's own proportions inside the square, centered.
        FitImageToBox(m.logo, 52, 88, 144, 144, "center", "center")
        content = m.top.itemContent
        if content <> invalid
            rawLogo = ""
            if content.addonLogo <> invalid then rawLogo = StringOf(content.addonLogo).Trim()
            m.isPlaceholder = IsPlaceholderLogo(rawLogo)
        end if
        UpdateLook()
    end if
end sub

sub onFocusChanged()
    UpdateLook()
end sub

sub UpdateLook()
    if m.face = invalid or m.border = invalid then return
    t = Theme()
    focused = m.top.itemHasFocus = true
    rowFocused = m.top.rowHasFocus = true

    if focused
        m.border.blendColor = "0xFFFFFFE6"
        m.face.blendColor = "0x221F38FF"
        m.name.color = t.textPrimary
        m.version.color = t.textSecondary
        m.scope.color = t.textSecondary
        m.description.color = t.textPrimary
        m.action.color = t.textPrimary
    else
        ' Stremio add-on card: rgba(255,255,255,0.05), no border.
        m.border.blendColor = "0x00000000"
        m.face.blendColor = "0xFFFFFF0D"
        m.name.color = t.textPrimary
        m.version.color = t.textSecondary
        m.scope.color = t.textSecondary
        m.description.color = t.textSecondary
        m.action.color = t.textSecondary
    end if

    if m.logoBg <> invalid
        if focused
            m.logoBg.opacity = 1
            m.logoBg.blendColor = t.screenBg
        else
            m.logoBg.opacity = 0
        end if
    end if
    m.logo.blendColor = "0xFFFFFFFF"

    m.top.opacity = 1.0
end sub

function RokuLogoUri(uri as dynamic) as string
    value = StringOf(uri).Trim()
    if value = "" then return ""
    path = value
    queryStart = value.InStr("?")
    if queryStart >= 0 then path = value.Left(queryStart)
    if path.Len() < 4 then return value
    if LCase(path.Right(4)) <> ".svg" then return value
    return value.Left(path.Len() - 4) + ".png" + value.Mid(path.Len())
end function
