# 🌸 Arona Soft Lavender — macOS Rice & Dotfiles

> A clean, aesthetic, and functional tiling desktop setup for **macOS (Apple Silicon)**, themed around a harmonious **Soft Lavender & Blue Archive Arona** palette. Designed with notch awareness for MacBook Air and Pro displays.

![Desktop Preview](assets/desktop.png)

---

## 📑 Table of Contents
- [✨ Features](#-features)
- [📦 Components](#-components)
- [⌨️ Keybindings (skhd)](#️-keybindings-skhd)
- [🛠️ Requirements & Dependencies](#️-requirements--dependencies)
- [🚀 Installation](#-installation)
- [🎨 Color Palette](#-color-palette)
- [📐 Notch Handling](#-notch-handling)

---

## ✨ Features

- **Dynamic Island Bar (SketchyBar):** Floating pills with soft purple border glow, dynamic spaces, audio visualizer (Cava), CPU graph with per-core usage popups, RAM monitor, Wi-Fi speed & IP info, weather forecast, and system stats.
- **MacBook Notch Adaptation:** Notch-aware application menu bar that automatically splits across the MacBook display notch, keeping the layout perfectly symmetrical and clean.
- **Fluid Tiling Window Management (Yabai):** Fast BSP auto-tiling with smart float toggling for multi-window applications, custom rules for dialogs, and smooth window animations.
- **Translucent Terminal (Kitty):** 85% opacity with 30px frosted glass blur, JetBrains Mono Nerd Font, powerline tabs, and custom Arona color scheme.
- **Rofi-style App & Directory Launcher:** Fast keyboard-driven launcher for macOS apps and frequent directories.
- **Square Window Corners (SquareCorners tweak):** Objective-C tweak to eliminate rounded corners on macOS windows for an ultra-sharp modern aesthetic.

---

## 📦 Components

| Component | Path | Description |
| :--- | :--- | :--- |
| **SketchyBar** | [`sketchybar/`](sketchybar/) | Lua-configured status bar with custom widgets & C helpers |
| **Kitty** | [`kitty/`](kitty/) | Fast GPU-accelerated terminal with blur & custom theme |
| **Yabai** | [`yabai/`](yabai/) | Tiling window manager config, rules, and scripts |
| **Skhd** | [`skhd/`](skhd/) | Keyboard hotkey daemon configuration |
| **Rofi Launcher** | [`rofi/`](rofi/) | Python-based quick application & folder launcher |
| **SquareCorners** | [`square_corners/`](square_corners/) | Ammonia DYLD injection tweak for square window corners |
| **Wallpapers** | [`wallpapers/`](wallpapers/) | High-resolution desktop wallpapers |

---

## ⌨️ Keybindings (skhd)

The setup uses `Option` (`Alt`) as the primary modifier key.

### 🧭 Window Focus & Navigation
| Shortcut | Action |
| :--- | :--- |
| <kbd>Alt</kbd> + <kbd>H</kbd> | Focus window to the **west** (left) |
| <kbd>Alt</kbd> + <kbd>J</kbd> | Focus window to the **south** (down) |
| <kbd>Alt</kbd> + <kbd>K</kbd> | Focus window to the **north** (up) |
| <kbd>Alt</kbd> + <kbd>L</kbd> | Focus window to the **east** (right) |

### 🔀 Window Moving & Layout
| Shortcut | Action |
| :--- | :--- |
| <kbd>Shift</kbd> + <kbd>Alt</kbd> + <kbd>H</kbd> / <kbd>J</kbd> / <kbd>K</kbd> / <kbd>L</kbd> | **Warp** window (insert into split in that direction) |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>H</kbd> / <kbd>J</kbd> / <kbd>K</kbd> / <kbd>L</kbd> | **Swap** active window with neighbor |
| <kbd>Alt</kbd> + <kbd>B</kbd> | **Balance** all window sizes in the space |
| <kbd>Alt</kbd> + <kbd>R</kbd> | **Rotate** layout tree by 90° |
| <kbd>Alt</kbd> + <kbd>E</kbd> | Toggle vertical / horizontal **split** orientation |
| <kbd>Alt</kbd> + <kbd>M</kbd> | Mirror space layout on Y-axis |
| <kbd>Shift</kbd> + <kbd>Alt</kbd> + <kbd>M</kbd> | Mirror space layout on X-axis |

### 🪟 Window State & Resizing
| Shortcut | Action |
| :--- | :--- |
| <kbd>Alt</kbd> + <kbd>Space</kbd> | **Smart Toggle Float** (floating mode for active window) |
| <kbd>Alt</kbd> + <kbd>F</kbd> | Toggle fullscreen zoom |
| <kbd>Alt</kbd> + <kbd>W</kbd> | Close active window |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Arrow Left/Right</kbd> | Resize window width |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Arrow Up/Down</kbd> | Resize window height |

### 🚀 Applications & Workspaces
| Shortcut | Action |
| :--- | :--- |
| <kbd>Alt</kbd> + <kbd>Enter</kbd> | Open new **Kitty** terminal window |
| <kbd>Cmd</kbd> + <kbd>Space</kbd> or <kbd>Alt</kbd> + <kbd>D</kbd> | Open **Application Launcher** |
| <kbd>Alt</kbd> + <kbd>1</kbd> .. <kbd>4</kbd> | Switch to workspace (Space) 1, 2, 3, or 4 |

---

## 🛠️ Requirements & Dependencies

### Core Utilities
Install the required packages via [Homebrew](https://brew.sh):

```bash
# Tiling Window Manager & Hotkey Daemon
brew install koekeishiya/formulae/yabai
brew install koekeishiya/formulae/skhd

# Status Bar & Audio Visualizer
brew install felixkratz/formulae/sketchybar
brew install cava
brew install jq

# Terminal
brew install --cask kitty
```

### Fonts
The rice requires **JetBrainsMono Nerd Font** and **sketchybar-app-font** for icons:

```bash
brew install --cask font-jetbrains-mono-nerd-font

# Sketchybar app font
curl -s https://github.com/kvndrsslr/sketchybar-app-font/releases/latest/download/sketchybar-app-font.ttf \
  -o ~/Library/Fonts/sketchybar-app-font.ttf
```

---

## 🚀 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Mellvazoa/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

2. **Run the installation script:**
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
   *The script creates symlinks into `~/.config/` and automatically compiles the SketchyBar C helper binaries.*

3. **Start or reload background services:**
   ```bash
   yabai --restart-service
   skhd --restart-service
   sketchybar --reload
   ```

4. *(Optional)* **Build SquareCorners tweak:**
   If you use Ammonia or another DYLD injection manager for square corners:
   ```bash
   cd square_corners
   make
   sudo make install
   ```

---

## 🎨 Color Palette

| Token | Hex | Role |
| :--- | :--- | :--- |
| **Accent / Lavender** | `#c8b4fa` | Active borders, highlights, tab selection, cursor |
| **Background / Dark Navy** | `#14172f` | Terminal & popup background |
| **Bar Island Background** | `#131630` (`85%`) | Sketchybar floating pills |
| **Foreground / Soft White** | `#f0edfc` | Text and icons |
| **Halo Cyan** | `#8ae1e8` | Accent highlights & info indicators |
| **Soft Pink** | `#fc7a95` | Warnings & battery alerts |

---

## 📐 Notch Handling

On MacBook models with camera notches (like the MacBook Air M3 13", where the notch spans from $X = 646\text{px}$ to $825\text{px}$):
- SketchyBar's menu bar is split dynamically into two brackets:
  - **Left island:** items 1–9 (`App` through `Window`) snug against the left edge of the notch ($X = 646\text{px}$).
  - **Right island:** items 10+ (`Help`, etc.) starting immediately at the right edge of the notch ($X = 825\text{px}$).
- For applications with fewer items (e.g., Finder), the right island and spacer are automatically hidden.
