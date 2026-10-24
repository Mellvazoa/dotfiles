#!/usr/bin/env bash

# Query currently focused window
win_json=$(yabai -m query --windows --window 2>/dev/null)
if [ -z "$win_json" ] || [ "$win_json" = "null" ]; then
    exit 0
fi

win_id=$(echo "$win_json" | jq -r '.id')
app=$(echo "$win_json" | jq -r '.app')
is_floating=$(echo "$win_json" | jq -r '."is-floating"')

if [ "$is_floating" = "true" ]; then
    # Window is currently floating -> Tile it into the layout
    yabai -m window "$win_id" --toggle float
    sleep 0.08

    # Double check if window actually became managed
    tiled_check=$(yabai -m query --windows --window "$win_id" 2>/dev/null | jq -r '."is-floating"')
    if [ "$tiled_check" = "true" ]; then
        yabai -m window "$win_id" --toggle float
        sleep 0.08
    fi

    # Measure geometry to detect any off-screen overflow or neighbor overlap
    disp_w=$(yabai -m query --displays --display 2>/dev/null | jq -r '.frame.w // 1470' | cut -d'.' -f1)
    max_x=$(( disp_w - 6 ))

    win_frame=$(yabai -m query --windows --window "$win_id" 2>/dev/null | jq -r '.frame')
    cur_x=$(echo "$win_frame" | jq -r '.x // 0' | cut -d'.' -f1)
    cur_w=$(echo "$win_frame" | jq -r '.w // 0' | cut -d'.' -f1)
    end_x=$(( cur_x + cur_w ))

    # Case A: Window is placed on the right and overflows the right edge of the screen
    if [ "$end_x" -gt "$max_x" ]; then
        overflow=$(( end_x - max_x + 8 ))
        yabai -m window "$win_id" --resize left:-$overflow:0 2>/dev/null || \
        yabai -m window "$win_id" --resize right:$overflow:0 2>/dev/null
    fi

    # Case B: Window is on the left and overflows into the neighbor to the right
    if [ "$cur_x" -lt 50 ]; then
        next_x=$(yabai -m query --windows --space 2>/dev/null | jq "[.[] | select(.id != $win_id and (.\"is-floating\" == false) and .\"is-visible\" == true and .frame.x > $cur_x)] | sort_by(.frame.x) | .[0].frame.x // 0" | cut -d'.' -f1)
        if [ "$next_x" -gt 0 ] && [ "$end_x" -gt "$next_x" ]; then
            overlap=$(( end_x - next_x + 8 ))
            yabai -m window "$win_id" --resize right:$overlap:0 2>/dev/null || \
            yabai -m window "$win_id" --resize left:-$overlap:0 2>/dev/null
        fi
    fi

else
    # Window is currently tiled -> Float it back
    yabai -m window "$win_id" --toggle float
    sleep 0.05

    # Center floating window nicely
    yabai -m window "$win_id" --grid 10:10:1:1:8:8 2>/dev/null

    # Rebalance remaining tiled windows so no void is left
    yabai -m space --balance 2>/dev/null
fi
