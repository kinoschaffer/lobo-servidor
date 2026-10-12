extends RefCounted
const COLORS := [Color("28c9c9"),Color("ed7770"),Color("edc34d"),Color("a788df"),Color("6799e2"),Color("86c968"),Color("ef9ac4"),Color("e6a061")]
const COLOR_NAMES := ["Turquesa","Coral","Miel","Lavanda","Azul","Lima","Rosa","Mandarina"]
const EYES := ["Clásicos","Soñolientos","Pestañas","Estrellados"]
const MOUTHS := ["Sonrisa","Discreta","Dientito","Gatuna"]
const HATS := ["Sin sombrero","Gorro de lana","Flor","Sombrero lunar","Corona","Gorra"]
const LIMITS := {"color":8,"eyes":4,"mouth":4,"hat":6}
static func normalize(value: Variant, fallback_color: int=0) -> Dictionary:
    var data: Dictionary=value if value is Dictionary else {}
    var result: Dictionary={}
    for key in LIMITS:
        var fallback:=clampi(fallback_color,0,7) if key=="color" else 0
        var v: Variant=data.get(key,fallback)
        result[key]=clampi(int(v),0,int(LIMITS[key])-1) if (v is int or v is float) and is_finite(float(v)) else fallback
    return result
static func load_local() -> Dictionary:
    var cfg:=ConfigFile.new()
    if cfg.load("user://apariencia.cfg")!=OK:
        var prefs:=ConfigFile.new()
        prefs.load("user://preferencias.cfg")
        return normalize({"color":prefs.get_value("player","color",0)})
    var data: Dictionary={}
    for key in LIMITS: data[key]=cfg.get_value("avatar",key,0)
    return normalize(data)
static func save_local(value: Dictionary) -> Error:
    var cfg:=ConfigFile.new()
    var safe:=normalize(value)
    for key in LIMITS: cfg.set_value("avatar",key,safe[key])
    return cfg.save("user://apariencia.cfg")
