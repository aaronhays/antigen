#!/bin/zsh

# Each line in this string has the following entries separated by a space
# character.
# <bundle-name>, <repo-url>, <plugin-location>, <repo-local-clone-dir>,
# <bundle-type>
# FIXME: Is not kept local by zsh!
local _ANTIGEN_BUNDLE_RECORD=""

# Syntaxes
#   bundle <url> [<loc>=/] [<name>]
bundle () {

    # Bundle spec arguments' default values.
    local url="$ANTIGEN_DEFAULT_REPO_URL"
    local loc=/
    local name=
    local btype=plugin
    local load=true

    # Set spec values based on the positional arguments.
    local position_args='url loc name'
    local i=1
    while ! [[ -z $1 || $1 == --*=* ]]; do
        local arg_name="$(echo "$position_args" | cut -d\  -f$i)"
        local arg_value="$1"
        eval "local $arg_name='$arg_value'"
        shift
        i=$(($i + 1))
    done

    # Check if url is just the plugin name. Super short syntax.
    if [[ "$url" != */* ]]; then
        loc="plugins/$url"
        url="$ANTIGEN_DEFAULT_REPO_URL"
    fi

    # Set spec values from keyword arguments, if any. The remaining arguments
    # are all assumed to be keyword arguments.
    while [[ $1 == --*=* ]]; do
        local arg_name="$(echo "$1" | cut -d= -f1 | sed 's/^--//')"
        local arg_value="$(echo "$1" | cut -d= -f2)"
        eval "local $arg_name='$arg_value'"
        shift
    done

    # Resolve the url.
    if [[ $url != git://* && $url != https://* ]]; then
        url="${url%.git}"
        test -z "$name" && name="$(basename "$url")"
        url="https://github.com/$url.git"
    fi

    # Plugin's repo will be cloned here.
    local clone_dir="$ADOTDIR/repos/$(echo "$url" \
        | sed -e 's/\.git$//' -e 's./.-SLASH-.g' -e 's.:.-COLON-.g')"

    # Make an intelligent guess about the name of the plugin, if not already
    # done or is explicitly specified.
    if [[ -z $name ]]; then
        name="$(basename $(echo $url | sed 's/\.git$//')/$loc)"
    fi

    # Add it to the record.
    _ANTIGEN_BUNDLE_RECORD="$_ANTIGEN_BUNDLE_RECORD\n$name $url $loc $clone_dir $btype"

    # Load it, unless specified otherwise.
    if $load; then
        # bundle-load "$name"
        bundle-load "$clone_dir/$loc" "$btype"
    fi
}

bundle-install () {

    local update=false
    if [[ $1 == --update ]]; then
        update=true
        shift
    fi

    mkdir -p "$ADOTDIR/bundles"

    local handled_repos=""
    local install_bundles=""

    if [[ $# != 0 ]]; then
        # Record and install just the given plugin here and now.
        bundle "$@"
        install_bundles="$(-bundle-echo-record | tail -1)"
    else
        # Install all the plugins, previously recorded.
        install_bundles="$(-bundle-echo-record)"
    fi

    # If the above `if` is directly piped to the below `while`, the contents
    # inside the `if` construct are run in a new subshell, so changes to the
    # `$_ANTIGEN_BUNDLE_RECORD` variable are lost after the `if` construct
    # finishes. So, we need the temporary `$install_bundles` variable.
    echo "$install_bundles" | while read spec; do

        local name="$(echo "$spec" | awk '{print $1}')"
        local url="$(echo "$spec" | awk '{print $2}')"
        local loc="$(echo "$spec" | awk '{print $3}')"
        local clone_dir="$(echo "$spec" | awk '{print $4}')"
        local btype="$(echo "$spec" | awk '{print $5}')"

        if [[ -z "$(echo "$handled_repos" | grep -Fm1 "$url")" ]]; then
            if [[ ! -d $clone_dir ]]; then
                git clone "$url" "$clone_dir"
            elif $update; then
                git --git-dir "$clone_dir/.git" pull
            fi

            handled_repos="$handled_repos\n$url"
        fi

        if [[ $name != *.theme ]]; then
            echo Installing $name
            local bundle_dest="$ADOTDIR/bundles/$name"
            test -e "$bundle_dest" && rm -rf "$bundle_dest"
            ln -s "$clone_dir/$loc" "$bundle_dest"
        else
            mkdir -p "$ADOTDIR/bundles/$name"
            cp "$clone_dir/$loc" "$ADOTDIR/bundles/$name"
        fi

        bundle-load "$clone_dir/$loc" "$btype"

    done

    # Initialize completions after installing
    bundle-apply

}

bundle-install! () {
    bundle-install --update
}

bundle-cleanup () {

    if [[ ! -d "$ADOTDIR/bundles" || \
        "$(ls "$ADOTDIR/bundles/" | wc -l)" == 0 ]]; then
        echo "You don't have any bundles."
        return 0
    fi

    # Find directores in ADOTDIR/bundles, that are not in the bundles record.
    local unidentified_bundles="$(comm -13 \
        <(-bundle-echo-record | awk '{print $1}' | sort) \
        <(ls -1 "$ADOTDIR/bundles"))"

    if [[ -z $unidentified_bundles ]]; then
        echo "You don't have any unidentified bundles."
        return 0
    fi

    echo The following bundles are not recorded:
    echo "$unidentified_bundles" | sed 's/^/  /'

    echo -n '\nDelete them all? [y/N] '
    if read -q; then
        echo
        echo
        echo "$unidentified_bundles" | while read name; do
            echo -n Deleting $name...
            rm -rf "$ADOTDIR/bundles/$name"
            echo ' done.'
        done
    else
        echo
        echo Nothing deleted.
    fi
}

bundle-load () {

    local location="$1"
    local btype="$2"

    if [[ $btype == theme ]]; then

        # Of course, if its a theme, the location would point to the script
        # file.
        source "$location"

    else

        # Source the plugin script
        # FIXME: I don't know. Looks very very ugly. Needs a better
        # implementation once tests are ready.
        local script_loc="$(ls "$location" | grep -m1 '.plugin.zsh$')"
        if [[ -f $script_loc ]]; then
            # If we have a `*.plugin.zsh`, source it.
            source "$script_loc"
        elif [[ ! -z "$(ls "$location" | grep -m1 '.zsh$')" ]]; then
            # If there is no `*.plugin.zsh` file, source *all* the `*.zsh`
            # files.
            for script ($location/*.zsh) source "$script"
        fi

        # Add to $fpath, for completion(s)
        fpath=($location $fpath)

    fi

}

bundle-lib () {
    bundle --loc=lib
}

bundle-theme () {
    local url="$ANTIGEN_DEFAULT_REPO_URL"
    local name="${1:-robbyrussell}"
    bundle --loc=themes/$name.zsh-theme --btype=theme
}

bundle-apply () {
    # Initialize completion.
    # TODO: Doesn't look like this is really necessary. Need to investigate.
    compinit -i
}

bundle-list () {
    # List all currently installed bundles
    if [[ -z "$_ANTIGEN_BUNDLE_RECORD" ]]; then
        echo "You don't have any bundles." >&2
        return 1
    else
        -bundle-echo-record | awk '{print $1 " " $2 " " $3}'
    fi
}

# Echo the bundle specs as in the record. The first line is not echoed since it
# is a blank line.
-bundle-echo-record () {
    echo "$_ANTIGEN_BUNDLE_RECORD" | sed -n '1!p'
}

-bundle-env-setup () {
    # Pre-startup initializations
    -set-default ANTIGEN_DEFAULT_REPO_URL \
        https://github.com/robbyrussell/oh-my-zsh.git
    -set-default ADOTDIR $HOME/.antigen

    # Load the compinit module
    autoload -U compinit

    # Without the following, `compdef` function is not defined.
    compinit -i
}

# Same as `export $1=$2`, but will only happen if the name specified by `$1` is
# not already set.
-set-default () {
    local arg_name="$1"
    local arg_value="$2"
    eval "test -z \"\$$arg_name\" && export $arg_name='$arg_value'"
}

-bundle-env-setup
