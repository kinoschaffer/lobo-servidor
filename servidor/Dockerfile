FROM debian:bookworm-slim
ARG GODOT_VERSION=4.7
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 libx11-6 libxcursor1 libxinerama1 libgl1 libxi6 libxrandr2 libasound2 libpulse0 libvulkan1 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -o /tmp/godot.zip && unzip /tmp/godot.zip -d /tmp/godot && mv /tmp/godot/Godot* /usr/local/bin/godot && chmod +x /usr/local/bin/godot && rm -rf /tmp/godot /tmp/godot.zip
WORKDIR /app
COPY servidor/project.server.godot ./project.godot
COPY servidor/salas.tscn servidor/salas_v040.gd ./servidor/
COPY scripts/mesa_sesion_v040.gd scripts/partida_motor.gd scripts/cosmeticos_v043.gd ./scripts/
COPY datos/reglas_v0_1.json ./datos/
RUN useradd -m lobo && chown -R lobo:lobo /app
USER lobo
EXPOSE 9080
CMD ["godot","--headless","--path","/app","res://servidor/salas.tscn"]

