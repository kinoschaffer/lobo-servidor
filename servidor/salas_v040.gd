extends Node
const Session = preload("res://scripts/mesa_sesion_v040.gd")
const LIMITS := {"role_assignment":90.0,"night":60.0,"dawn":60.0,"discussion":120.0,"vote":45.0}
var tcp := TCPServer.new()
var peers: Dictionary = {}
var rooms: Dictionary = {}
var serial := 0
var clock := 0.0

func _ready() -> void:
    var port := int(OS.get_environment("PORT")) if OS.has_environment("PORT") else 9080
    var err := tcp.listen(port,"0.0.0.0")
    if err != OK:
        push_error("No se pudo abrir el puerto del servidor: "+str(err))
        get_tree().quit(1)
    else: print("LOBO_SERVER_READY port=",port)

func _process(delta: float) -> void:
    clock += delta
    while tcp.is_connection_available():
        var stream := tcp.take_connection()
        if peers.size()>=128: stream.disconnect_from_host(); continue
        serial += 1
        var ws := WebSocketPeer.new()
        ws.inbound_buffer_size = 32768
        ws.outbound_buffer_size = 262144
        ws.max_queued_packets = 128
        ws.accept_stream(stream)
        peers[serial] = {"socket":ws,"room":"","slot":-1,"last":clock,"budget":50.0,"voice_budget":32.0}
    for key in peers.keys():
        var p: Dictionary = peers[key]
        p.budget = minf(50.0,float(p.budget)+delta*12.0)
        p.voice_budget = minf(32.0,float(p.voice_budget)+delta*27.0)
        var ws: WebSocketPeer = p.socket
        ws.poll()
        if ws.get_ready_state()==WebSocketPeer.STATE_OPEN:
            var count := 0
            while ws.get_available_packet_count()>0 and count<40:
                count += 1
                var packet := ws.get_packet()
                p.last = clock
                if ws.was_string_packet():
                    if packet.size()>8192 or float(p.budget)<1.0: ws.close(1008,"Límite de mensajes"); break
                    p.budget -= 1.0
                    var value: Variant = JSON.parse_string(packet.get_string_from_utf8())
                    if value is Dictionary: _message(int(key),value)
                else: _voice(int(key),packet)
        elif ws.get_ready_state()==WebSocketPeer.STATE_CLOSED or clock-float(p.last)>180.0:
            ws.close()
            var code := str(p.room)
            peers.erase(key)
            if rooms.has(code): _broadcast(code)
    for code in rooms.keys():
        var room: Dictionary = rooms[code]
        if _connections(code).is_empty():
            room.idle = float(room.idle)+delta
            if float(room.idle)>900.0: rooms.erase(code)
            continue
        room.idle = 0.0
        if room.session != null:
            var session = room.session
            session.phase_seconds += delta
            var limit := float(LIMITS.get(str(session.engine.phase),999999.0))
            if session.phase_seconds>=limit:
                session.expire_phase()
                _broadcast(code)

func _connections(code: String) -> Array:
    var found: Array = []
    for key in peers:
        if str(peers[key].room)==code: found.append(key)
    return found

func _send(key: int, data: Dictionary) -> void:
    if peers.has(key) and peers[key].socket.get_ready_state()==WebSocketPeer.STATE_OPEN:
        peers[key].socket.send_text(JSON.stringify(data))

func _error(key: int, message: String) -> void:
    _send(key,{"type":"error","message":message})

func _message(key: int, data: Dictionary) -> void:
    var p: Dictionary = peers[key]
    var op := str(data.get("op",""))
    if op=="ping": _send(key,{"type":"pong"}); return
    if op in ["create","join","resume"]:
        if not str(p.room).is_empty(): _error(key,"Ya estás en una sala."); return
        var code := str(data.get("code","")).strip_edges().to_upper()
        if op=="create":
            if rooms.size()>=64: _error(key,"Servidor ocupado. Probá más tarde."); return
            code = Crypto.new().generate_random_bytes(4).hex_encode().left(6).to_upper()
            while rooms.has(code): code=Crypto.new().generate_random_bytes(4).hex_encode().left(6).to_upper()
            rooms[code]={"members":[],"session":null,"idle":0.0}
        if not rooms.has(code): _error(key,"No existe esa sala."); return
        var room: Dictionary = rooms[code]
        var slot := -1
        if op=="resume":
            var token := str(data.get("token",""))
            for member in room.members:
                if token.length()==64 and str(member.token)==token: slot=int(member.id)
            if slot<0: _error(key,"La sesión ya no está disponible."); return
            for other in _connections(code):
                if int(peers[other].slot)==slot:
                    peers[other].room=""
                    peers[other].socket.close(1000,"Sesión recuperada")
        else:
            if room.session!=null: _error(key,"La partida ya empezó."); return
            if room.members.size()>=8: _error(key,"La sala está llena."); return
            slot=room.members.size()
            var nickname := str(data.get("name","Jugador")).strip_edges().left(20)
            if nickname.is_empty(): nickname="Jugador "+str(slot+1)
            room.members.append({"id":slot,"name":nickname,"token":Crypto.new().generate_random_bytes(32).hex_encode()})
        p.room=code
        p.slot=slot
        _send(key,{"type":"joined","code":code,"id":slot,"token":room.members[slot].token})
        _broadcast(code)
        return
    var code := str(p.room)
    if not rooms.has(code): _error(key,"Primero entrá a una sala."); return
    var room: Dictionary = rooms[code]
    if op=="start":
        var connected := _connections(code)
        if connected.is_empty() or key!=int(connected[0]): _error(key,"Solo el anfitrión puede empezar."); return
        if room.session!=null: return
        if connected.size()<2: _error(key,"Se necesitan al menos dos personas. Los demás serán bots."); return
        var active_members: Array=[]
        for index in range(connected.size()):
            var peer_id: int=int(connected[index])
            var old_slot: int=int(peers[peer_id].slot)
            var member: Dictionary=room.members[old_slot].duplicate()
            member.id=index
            peers[peer_id].slot=index
            active_members.append(member)
            _send(peer_id,{"type":"joined","code":code,"id":index,"token":member.token})
        room.members=active_members
        room.session=Session.new()
        var names: Array = []
        for member in room.members: names.append(str(member.name))
        room.session.start(names)
    elif room.session!=null:
        var result: Dictionary=room.session.command(int(p.slot),data)
        if not bool(result.get("ok",false)): _error(key,str(result.get("error","Acción inválida"))); return
    else: _error(key,"Esperá a que empiece la partida."); return
    _broadcast(code)

func _broadcast(code: String) -> void:
    var room: Dictionary = rooms[code]
    var connected := _connections(code)
    var roster: Array = []
    for member in room.members:
        var online := false
        for key in connected:
            if int(peers[key].slot)==int(member.id): online=true
        roster.append({"id":member.id,"name":member.name,"connected":online})
    for key in connected:
        if room.session==null:
            _send(key,{"type":"lobby","code":code,"members":roster,"host":key==connected[0]})
        else:
            var filtered: Dictionary=room.session.view(int(peers[key].slot))
            filtered["seconds_left"]=maxf(0.0,float(LIMITS.get(str(room.session.engine.phase),0.0))-float(room.session.phase_seconds))
            _send(key,{"type":"state","view":filtered,"code":code,"members":roster})

func _voice(key: int, packet: PackedByteArray) -> void:
    var p: Dictionary = peers[key]
    if packet.size()!=1280 or float(p.voice_budget)<1.0: return
    p.voice_budget-=1.0
    var code := str(p.room)
    if not rooms.has(code): return
    var room: Dictionary = rooms[code]
    if room.session!=null:
        var own: Dictionary=room.session.view(int(p.slot))
        if not bool(own.get("voice_allowed",false)): return
    var framed := PackedByteArray([int(p.slot)])
    framed.append_array(packet)
    for other in _connections(code):
        if other==key: continue
        var ws: WebSocketPeer=peers[other].socket
        if ws.get_current_outbound_buffered_amount()<8192: ws.put_packet(framed)

func _exit_tree() -> void:
    tcp.stop()
    for p in peers.values(): p.socket.close()

