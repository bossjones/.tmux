#!/usr/bin/env bash

mkdir -p ~/.bin || true
curl -L 'https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux' > ~/.bin/fzf-tmux
chmod +x ~/.bin/fzf-tmux

echo "Setting ~/.bin/tmux_colors.sh..."
bash -c 'cat >> ~/.bin/tmux_colors.sh << \EOF
    #! /bin/bash
    for i in {0..255} ; do
        printf "\x1b[38;5;${i}mcolour${i}\n"
    done
EOF'

chmod +x ~/.bin/tmux_colors.sh


git clone git@github.com:kevinhwang91/fzf-tmux-script.git ~/dev/fzf-tmux-script || true
cd ~/dev/fzf-tmux-script
git pull --rebase || true
cd -
cp -av ~/dev/fzf-tmux-script/panes/fzf-panes.tmux ~/.bin/fzf-panes.tmux
cp -av ~/dev/fzf-tmux-script/popup/fzfp ~/.bin/fzfp
