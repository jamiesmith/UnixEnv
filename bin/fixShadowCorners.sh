#!/bin/bash

export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin/"

VERBOSE=""

function die_usage
{
    echo "Usage: $0 [-c][-n pixels to nuke][-s suffix][-v] images"
    echo " -n <number of pixels> default is $nuke"
    echo " -s <suffix to add> default is $suffix"
    echo " -v verbose"
    echo "$*"
    exit 9
}

function fixImage
{
    theImage="$1"
    # The black bar on the top is an issue.
    # Grab the color from one pixel above nuke on each side
    #
    dpi=$(magick "$theImage"  -format "%x" info:)

    local pixelsToNuke=$nuke
    cornerAllowance=3
    
    [ $dpi -gt 100 ] && pixelsToNuke=$((nuke*2)) && cornerAllowance=$((cornerAllowance*2))

    width=$(identify -format "%w" "$theImage")
    height=$(identify -format "%h" "$theImage")
    targetPixelTop=$((height-$pixelsToNuke-1))
    leftPixel="%[pixel:p{${cornerAllowance},${targetPixelTop}}]"
    rightPixel="%[pixel:p{$((width-${cornerAllowance})),${targetPixelTop}}]"
    leftFillColor=$(magick "$theImage"  -format "${leftPixel}" info:)
    rightFillColor=$(magick "$theImage"  -format "${rightPixel}" info:)
    
    # calculate the bottom left range
    heightOffset=$((height-$pixelsToNuke))
    widthOffset=$((width-$pixelsToNuke))

    # Switched this to triangles
    #
    # bottomLeft=$(printf "rectangle 0,%d %d,%d" "$heightOffset" "$pixelsToNuke" "$height")
    # bottomRight=$(printf "rectangle %d,%d %d,%d" "$widthOffset" "$heightOffset"  "$width" "$height")
    bottomLeft=$(printf "polygon 0,%d 0,%d %d,%d" "$heightOffset" "$height" "$pixelsToNuke" "$height")
    bottomRight=$(printf "polygon %d,%d %d,%d %d,%d" "$widthOffset" "$height" "$width"  "$heightOffset"  "$width" "$height")
    
    if [ -n "$VERBOSE" ]
    then
        echo "heightOffset : $heightOffset"
        echo "widthOffset  : $widthOffset"
        echo "pixelsToNuke : $pixelsToNuke"
        echo "width        : $width"
        echo "height       : $height"
        echo "bottomLeft   : $bottomLeft"
        echo "bottomRight  : $bottomRight"
        echo "leftFillColor: $leftFillColor"
        echo "rightFillColor: $rightFillColor"
    fi
    
    name=${theImage%.*}
    ext=${theImage##*.}

    echo "fixing $pixelsToNuke pixels on $theImage with $leftFillColor / $rightFillColor"

    magick "$theImage" -fill $leftFillColor  -draw "$bottomLeft"  "${name}${suffix}.$ext"

    magick "$theImage" -fill $rightFillColor -draw "$bottomRight" "${name}${suffix}.$ext"
}

[ -x "$(which magick)" ] || die_usage "ERROR: You need to install imagemagick - try brew install imagemagick or the linux equivalent"

# This is how much to nuke

nuke=12
os_ver=$(sw_vers -productVersion | cut -d'.' -f 1)
if [ $os_ver -ge 26 ]
then
    # echo bigger
    # Stupid Tahoe and the rounded corners
    nuke=26
else
    # echo smaller
    nuke=12
fi

suffix=""

while getopts "cn:s:v" option
do
    case $option in
	n)
	    nuke="$OPTARG"
	    ;;
    s)
    # Don't set it if it was already set
    #
        [ -n "$suffix" ] && suffix="$OPTARG"
        ;;
	v)
	    VERBOSE="yes"
	    ;;
	*)
	    die_usage "Wrong arg $option"

    esac
done
shift `expr $OPTIND - 1`

if [ $# -gt 0 ]
then
    for file in "$@"
    do
	fixImage "$file"
    done
else
    osascript -e 'display notification "Grabbing image from clipboard"'

    tmpName="/Users/$USER/TempPictures/shadow-corners.png"
    echo "TRYING IT!"
    
    # Save it from the clipboard to a temp file
    #
osascript <<END
on errorDialog(dialogText)
	display dialog dialogText buttons "OK" cancel button 1 default button 1 with title "Clipboard Image Save" with icon stop
end errorDialog

try
	set theImage to the clipboard as {«class PNGf»}
on error
	errorDialog("An image was not found on the clipboard.")
end try


try
	set openedFile to open for access "/Users/$USER/TempPictures/shadow-corners.png" with write permission
	write theImage to openedFile
	close access openedFile
on error
	try
		close access openedFile
	end try
end try

END

    # Fix the image
    #
    fixImage "$tmpName"
    
    # put it back on the clipboard
    #
    # osascript -e 'set the clipboard to POSIX file ("/tmp/foo.png")'
    # osascript -e 'set the clipboard to (read (POSIX file "/Users/$USER/TempPictures/shadow-corners.png") as picture)'
    osascript -e 'set the clipboard to (read (POSIX file ((POSIX path of (path to home folder)) & "TempPictures/shadow-corners.png")) as picture)'
    echo "image is back in the clipboard I think"
    osascript -e 'display notification "image is back in the clipboard I think"'
fi
