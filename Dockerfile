FROM barichello/godot-ci:4.5.2
WORKDIR /app
COPY . .
CMD ["godot", "--headless", "--export-release", "Linux/X11", "export/linux64/libsm64-godot-demo.x86_64"]
