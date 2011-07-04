#!/bin/sh

set -e

announce_list="xorg-announce@lists.freedesktop.org"
xorg_list="xorg@lists.freedesktop.org"
dri_list="dri-devel@lists.sourceforge.net"
xkb_list="xkb@listserv.bat.ru"

host_people=annarchy.freedesktop.org
host_xorg=xorg.freedesktop.org
host_dri=dri.freedesktop.org
user=
remote=origin
moduleset=

usage()
{
    cat <<HELP
Usage: `basename $0` [options] <section> <tag_previous> <tag_current>

Options:
  --force       force overwritting an existing release
  --user <name> username on $host_people
  --help        this help message
  --ignore-local-changes        don't abort on uncommitted local changes
  --remote      git remote where the change should be pushed (default "origin")
  --moduleset   jhbuild moduleset to update with relase info
HELP
}

abort_for_changes()
{
    cat <<ERR
Uncommitted changes found. Did you forget to commit? Aborting.
Use --ignore-local-changes to skip this check.
ERR
    exit 1
}

gen_announce_mail()
{
case "$tag_previous" in
initial)
	range="$tag_current"
	;;
*)
	range="$tag_previous".."$tag_current"
	;;
esac

MD5SUM=`which md5sum || which gmd5sum`
SHA1SUM=`which sha1sum || which gsha1sum`
SHA256SUM=`which sha256sum || which gsha256sum`

if [ "$section" = "libdrm" ]; then
    host=$host_dri
    list=$dri_list
elif [ "$section" = "xkeyboard-config" ]; then
    host=$host_xorg
    list=$xkb_list
else
    host=$host_xorg
    list=$xorg_list
fi

    cat <<RELEASE
Subject: [ANNOUNCE] $module $version
To: $announce_list
CC: $list

`git log --no-merges "$range" | git shortlog`

git tag: $tag_current

http://$host/$section_path/$tarbz2
MD5:  `cd $tarball_dir && $MD5SUM $tarbz2`
SHA1: `cd $tarball_dir && $SHA1SUM $tarbz2`
SHA256: `cd $tarball_dir && $SHA256SUM $tarbz2`

http://$host/$section_path/$targz
MD5:  `cd $tarball_dir && $MD5SUM $targz`
SHA1: `cd $tarball_dir && $SHA1SUM $targz`
SHA256: `cd $tarball_dir && $SHA256SUM $targz`

RELEASE
}

export LC_ALL=C

while [ $# != 0 ]; do
    case "$1" in
    --force)
        force="yes"
        shift
        ;;
    --help)
        usage
        exit 0
        ;;
    --user)
	shift
	user=$1@
	shift
	;;
    --ignore-local-changes)
        ignorechanges=1
        shift
        ;;
    --remote)
        shift
        remote=$1
        shift
        ;;
    --moduleset)
        shift
        moduleset=$1
        shift
        ;;
    --*)
        echo "error: unknown option"
        usage
        exit 1
        ;;
    *)
        if [ $# != 3 ]; then
            echo "error: invalid argument count"
            usage
            exit 1
        fi
        section="$1"
        tag_previous="$2"
        tag_current="$3"
        shift 3
        ;;
    esac
done

# Check for uncommitted/queued changes.
if [ "x$ignorechanges" != "x1" ]; then
    set +e
    git diff --quiet HEAD > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        abort_for_changes
    fi
    set -e
fi

# Check if the object has been pushed. Do do so
# 1. Check if the current branch has the object. If not, abort.
# 2. Check if the object is on $remote/branchname. If not, abort.
local_sha=`git rev-list -1 $tag_current`
current_branch=`git branch | grep "\*" | sed -e "s/\* //"`
set +e
git rev-list $current_branch | grep $local_sha > /dev/null
if [ $? -eq 1 ]; then
    echo "Cannot find tag '$tag_current' on current branch. Aborting."
    echo "Switch to the correct branch and re-run the script."
    exit 1
fi

revs=`git rev-list $remote/$current_branch..$current_branch | wc -l`
if [ $revs -ne 0 ]; then
    git rev-list $remote/$current_branch..$current_branch | grep $local_sha > /dev/null

    if [ $? -ne 1 ]; then
        echo "$remote/$current_branch doesn't have object $local_sha"
        echo "for tag '$tag_current'. Did you push branch first? Aborting."
        exit 1
    fi
fi
set -e

tarball_dir="$(dirname $(find . -name config.status))"
module="${tag_current%-*}"
if [ "x$module" = "x$tag_current" ]; then
    # version-number-only tag.
    pwd=`pwd`
    module=`basename $pwd`
    version="$tag_current"
else
    # module-and-version style tag
    version="${tag_current##*-}"
fi

detected_module=`grep 'PACKAGE = ' $tarball_dir/Makefile | sed 's|PACKAGE = ||'`
if [ -f $detected_module-$version.tar.bz2 ]; then
    module=$detected_module
fi

modulever=$module-$version
tarbz2="$modulever.tar.bz2"
targz="$modulever.tar.gz"
announce="$tarball_dir/$modulever.announce"

echo "checking parameters"
if ! [ -f "$tarball_dir/$tarbz2" ] ||
   ! [ -f "$tarball_dir/$targz" ]; then
    echo "error: tarballs not found.  Did you run make dist?"
    usage
    exit 1
fi

if [ -z "$tag_previous" ] ||
   [ -z "$section" ]; then
    echo "error: previous tag or section not found."
    usage
    exit 1
fi

if [ -n "$moduleset" ]; then
    echo "checking for moduleset"
    if ! [ -w "$moduleset" ]; then
        echo "moduleset $moduleset does not exist or is not writable"
        exit 1
    fi
fi

if [ "$section" = "libdrm" ]; then
    section_path="libdrm"
    srv_path="/srv/$host_dri/www/$section_path"
elif [ "$section" = "xkeyboard-config" ]; then
    section_path="archive/individual/data"
    srv_path="/srv/$host_xorg/$section_path"
else
    section_path="archive/individual/$section"
    srv_path="/srv/$host_xorg/$section_path"
fi

echo "checking for proper current dir"
if ! [ -d .git ]; then
    echo "error: do this from your git dir, weenie"
    exit 1
fi

echo "checking for an existing tag"
if ! git tag -l $tag_current >/dev/null; then
    echo "error: you must tag your release first!"
    exit 1
fi

echo "checking for an existing release"
if ssh $user$host_people ls $srv_path/$targz >/dev/null 2>&1 ||
   ssh $user$host_people ls $srv_path/$tarbz2 >/dev/null 2>&1; then
    if [ "x$force" = "xyes" ]; then
        echo "warning: overriding released file ... here be dragons."
    else
        echo "error: file already exists!"
        exit 1
    fi
fi

echo "generating announce mail template, remember to sign it"
gen_announce_mail >$announce
echo "    at: $announce"

if [ -n "$moduleset" ]; then
    echo "updating moduleset $moduleset"
    real_script_path=`readlink -f "$0"`
    modulardir=`dirname "$real_script_path"`
    sha1sum=`cd $tarball_dir && $SHA1SUM $targz | cut -d' ' -f1`
    $modulardir/update-moduleset.sh $moduleset $sha1sum $targz
fi

echo "installing release into server"
scp $tarball_dir/$targz $tarball_dir/$tarbz2 $user$host_people:$srv_path

echo "pushing tag upstream"
git push $remote $tag_current

