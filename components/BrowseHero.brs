sub init()
    m.heroPoster = m.top.FindNode("heroPoster")
    m.heroPosterPrev = m.top.FindNode("heroPosterPrev")
    m.heroPosterFadeAnim = m.top.FindNode("heroPosterFadeAnim")
    m.heroPosterPrevFadeOutAnim = m.top.FindNode("heroPosterPrevFadeOutAnim")
    m.heroScrim = m.top.FindNode("heroScrim")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroRating = m.top.FindNode("heroRating")
    m.heroRatingText = m.top.FindNode("heroRatingText")
    m.heroGenres = m.top.FindNode("heroGenres")
    m.heroDescription = m.top.FindNode("heroDescription")
    m.heroTitleGrace = m.top.FindNode("heroTitleGrace")
    m.heroPosterLoader = m.top.FindNode("heroPosterLoader")
    m.heroLogoLoader = m.top.FindNode("heroLogoLoader")
    m.stores = invalid
    m.textsLanguage = ""
    m.heroPanel = false

    if m.heroPosterLoader <> invalid then m.heroPosterLoader.target = m.heroPoster
    if m.heroLogoLoader <> invalid then m.heroLogoLoader.target = m.heroLogo

    plw = m.top.posterLoadWidth
    plh = m.top.posterLoadHeight
    if plw <> invalid and plw > 0 and m.heroPoster <> invalid then m.heroPoster.loadWidth = plw
    if plh <> invalid and plh > 0 and m.heroPoster <> invalid then m.heroPoster.loadHeight = plh
    if plw <> invalid and plw > 0 and m.heroPosterPrev <> invalid then m.heroPosterPrev.loadWidth = plw
    if plh <> invalid and plh > 0 and m.heroPosterPrev <> invalid then m.heroPosterPrev.loadHeight = plh

    if m.heroPosterLoader <> invalid
        m.heroPosterLoader.ObserveField("ready", "HeroOnPosterStatus")
        m.heroPosterLoader.ObserveField("status", "HeroOnPosterStatus")
    else if m.heroPoster <> invalid
        m.heroPoster.ObserveField("loadStatus", "HeroOnPosterStatus")
    end if
    if m.heroLogoLoader <> invalid
        m.heroLogoLoader.ObserveField("ready", "HeroOnLogoStatus")
        m.heroLogoLoader.ObserveField("status", "HeroOnLogoStatus")
    else if m.heroLogo <> invalid
        m.heroLogo.ObserveField("loadStatus", "HeroOnLogoStatus")
    end if
    if m.heroTitleGrace <> invalid then m.heroTitleGrace.ObserveField("fire", "HeroOnTitleGraceFire")
    if m.heroPosterPrevFadeOutAnim <> invalid then m.heroPosterPrevFadeOutAnim.ObserveField("state", "HeroOnPosterPrevFadeOutState")

    HeroInitState()
    ApplyHeroTheme()
end sub

sub SetStores(storeHost as object, _scene = invalid as object)
    if storeHost = invalid
        m.stores = invalid
        m.textsLanguage = ""
        LoadTexts(invalid)
        return
    end if
    m.stores = {
        addons: storeHost
        auth: storeHost
        episodes: storeHost
        library: storeHost
        settings: storeHost
        texts: storeHost
        time: storeHost
        watch: storeHost
    }
    RefreshHeroTexts()
end sub

sub RefreshHeroTexts()
    if m.stores = invalid
        m.textsLanguage = ""
        LoadTexts(invalid)
        return
    end if
    currentLang = TextsLanguage()
    if m._texts <> invalid and m.textsLanguage = currentLang then return
    LoadTexts(m.stores.texts)
    m.textsLanguage = TextsLanguage()
end sub

' Stremio MetaPreview card: art on top, then logo/title, facts, genres and
' description inside a rounded card at the right edge.
sub ApplyPanelMode()
    m.heroPanel = m.top.panel = true
    card = m.top.FindNode("heroCard")
    fadeLR = m.top.FindNode("heroFadeLR")
    fadeBT = m.top.FindNode("heroFadeBT")
    if not m.heroPanel
        if card <> invalid then card.visible = false
        return
    end if
    if card <> invalid then card.visible = true
    for each node in [m.heroPoster, m.heroPosterPrev]
        node.translation = [1296, 60]
        node.width = 564
        node.height = 318
    end for
    if fadeLR <> invalid then fadeLR.visible = false
    if fadeBT <> invalid
        fadeBT.translation = [1296, 238]
        fadeBT.width = 564
        fadeBT.height = 140
    end if
    if m.heroScrim <> invalid then m.heroScrim.visible = false
    m.heroTitle.translation = [1328, 330]
    m.heroTitle.width = 500
    m.heroTitle.height = 100
    HeroPanelPlace()
end sub

sub ApplyHeroTheme()
    t = Theme()
    if m.heroScrim <> invalid then m.heroScrim.color = t.scrim
    if m.heroTitle <> invalid then m.heroTitle.color = t.textPrimary
    if m.heroMeta <> invalid then m.heroMeta.color = t.textSecondary
    if m.heroRatingText <> invalid then m.heroRatingText.color = t.accentWarm
    if m.heroGenres <> invalid then m.heroGenres.color = t.textSecondary
    if m.heroDescription <> invalid then m.heroDescription.color = t.textPrimary
end sub

sub Render(meta as object, fallbackType = "" as dynamic, posterFallback = true as dynamic)
    if m.stores <> invalid then RefreshHeroTexts()
    fbType = ""
    if fallbackType <> invalid then fbType = fallbackType
    pFallback = true
    if posterFallback <> invalid then pFallback = posterFallback
    HeroRender(meta, fbType, pFallback)
end sub

sub Clear()
    HeroClear()
end sub

function PosterReady() as boolean
    return HeroPosterReady()
end function
