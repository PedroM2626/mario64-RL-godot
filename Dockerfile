FROM barichello/godot-ci:4.3
WORKDIR /app
COPY . .
CMD ["godot", "--headless", "--export-release", "Linux/X11", "build/export.x86_64"]
