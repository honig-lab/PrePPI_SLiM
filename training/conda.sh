__conda_setup="$('/apps/ohpc/pub/apps/conda/3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/apps/ohpc/pub/apps/conda/3/etc/profile.d/conda.sh" ]; then
        . "/apps/ohpc/pub/apps/conda/3/etc/profile.d/conda.sh"
    else
        export PATH="/apps/ohpc/pub/apps/conda/3/bin:$PATH"
    fi
fi
unset __conda_setup

