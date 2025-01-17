#!/usr/bin/env bash

# Copyright (c) 2015-2019 Michael Klement mklement0@gmail.com (http://same2u.net), released under the MIT license.

###
# Home page: https://github.com/mklement0/fileicon
# Author:   Michael Klement <mklement0@gmail.com> (http://same2u.net)
# Invoke with:
#   --version for version information
#   --help for usage information
###

# --- STANDARD SCRIPT-GLOBAL CONSTANTS

kTHIS_NAME=${BASH_SOURCE##*/}
kTHIS_HOMEPAGE='https://github.com/mklement0/fileicon'
kTHIS_VERSION='v0.2.4' # NOTE: This assignment is automatically updated by `make version VER=<newVer>` - DO keep the 'v' prefix.

unset CDPATH  # To prevent unpredictable `cd` behavior.

# --- Begin: STANDARD HELPER FUNCTIONS

die() { echo "$kTHIS_NAME: ERROR: ${1:-"ABORTING due to unexpected error."}" 1>&2; exit ${2:-1}; }
dieSyntax() { echo "$kTHIS_NAME: ARGUMENT ERROR: ${1:-"Invalid argument(s) specified."} Use -h for help." 1>&2; exit 2; }

# SYNOPSIS
#   openUrl <url>
# DESCRIPTION
#   Opens the specified URL in the system's default browser.
openUrl() {
  local url=$1 platform=$(uname) cmd=()
  case $platform in
    'Darwin') # OSX
      cmd=( open "$url" )
      ;;
    'CYGWIN_'*) # Cygwin on Windows; must call cmd.exe with its `start` builtin
      cmd=( cmd.exe /c start '' "$url " )  # !! Note the required trailing space.
      ;;
    'MINGW32_'*) # MSYS or Git Bash on Windows; they come with a Unix `start` binary
      cmd=( start '' "$url" )
      ;;
    *) # Otherwise, assume a Freedesktop-compliant OS, which includes many Linux distros, PC-BSD, OpenSolaris, ...
      cmd=( xdg-open "$url" )
      ;;
  esac
  "${cmd[@]}" || { echo "Cannot locate or failed to open default browser; please go to '$url' manually." >&2; return 1; }
}

# Prints the embedded Markdown-formatted man-page source to stdout.
printManPageSource() {
  /usr/bin/sed -n -e $'/^: <<\'EOF_MAN_PAGE\'/,/^EOF_MAN_PAGE/ { s///; t\np;}' "$BASH_SOURCE"
}

# Opens the man page, if installed; otherwise, tries to display the embedded Markdown-formatted man-page source; if all else fails: tries to display the man page online.
openManPage() {
  local pager embeddedText
  if ! man 1 "$kTHIS_NAME" 2>/dev/null; then
    # 2nd attempt: if present, display the embedded Markdown-formatted man-page source
    embeddedText=$(printManPageSource)
    if [[ -n $embeddedText ]]; then
      pager='more'
      command -v less &>/dev/null && pager='less' # see if the non-standard `less` is available, because it's preferable to the POSIX utility `more`
      printf '%s\n' "$embeddedText" | "$pager"
    else # 3rd attempt: open the the man page on the utility's website
      openUrl "${kTHIS_HOMEPAGE}/doc/${kTHIS_NAME}.md"
    fi
  fi
}

# Prints the contents of the synopsis chapter of the embedded Markdown-formatted man-page source for quick reference.
printUsage() {
  local embeddedText
  # Extract usage information from the SYNOPSIS chapter of the embedded Markdown-formatted man-page source.
  embeddedText=$(/usr/bin/sed -n -e $'/^: <<\'EOF_MAN_PAGE\'/,/^EOF_MAN_PAGE/!d; /^## SYNOPSIS$/,/^#/{ s///; t\np; }' "$BASH_SOURCE")
  if [[ -n $embeddedText ]]; then
    # Print extracted synopsis chapter - remove backticks for uncluttered display.
    printf '%s\n\n' "$embeddedText" | tr -d '`'
  else # No SYNOPIS chapter found; fall back to displaying the man page.
    echo "WARNING: usage information not found; opening man page instead." >&2
    openManPage
  fi
}

# --- End: STANDARD HELPER FUNCTIONS

# ---  PROCESS STANDARD, OUTPUT-INFO-THEN-EXIT OPTIONS.
case $1 in
  --version)
    # Output version number and exit, if requested.
    ver="v0.2.4"; echo "$kTHIS_NAME $kTHIS_VERSION"$'\nFor license information and more, visit '"$kTHIS_HOMEPAGE"; exit 0
    ;;
  -h|--help)
    # Print usage information and exit.
    printUsage; exit
    ;;
  --man)
    # Display the manual page and exit.
    openManPage; exit
    ;;
  --man-source) # private option, used by `make update-doc`
    # Print raw, embedded Markdown-formatted man-page source and exit
    printManPageSource; exit
    ;;
  --home)
    # Open the home page and exit.
    openUrl "$kTHIS_HOMEPAGE"; exit
    ;;
esac

# --- Begin: SPECIFIC HELPER FUNCTIONS

# NOTE: The functions below operate on byte strings such as the one above:
#       A single single string of pairs of hex digits, without separators or line breaks.
#       Thus, a given byte position is easily calculated: to get byte $byteIndex, use
#         ${byteString:byteIndex*2:2}

# Outputs the specified EXTENDED ATTRIBUTE VALUE as a byte string (a hex dump that is a single-line string of pairs of hex digits, without separators or line breaks, such as "000A2C".
# IMPORTANT: Hex. digits > 9 use UPPPERCASE characters.
#   getAttribByteString <file> <attrib_name>
getAttribByteString() {
  xattr -px "$2" "$1" | tr -d ' \n'
  return ${PIPESTATUS[0]}
}

# Outputs the specified file's RESOURCE FORK as a byte string (a hex dump that is a single-line string of pairs of hex digits, without separators or line breaks, such as "000a2c".
# IMPORTANT: Hex. digits > 9 use *lowercase* characters.
# Note: This function relies on `xxd -p <file>/..namedfork/rsrc | tr -d '\n'` rather than the conceptually equivalent `getAttributeByteString <file> com.apple.ResourceFork`
#       for PERFORMANCE reasons: getAttributeByteString() relies on `xattr`, which is a *Python* script and therefore quite slow due to Python's startup cost.
#   getAttribByteString <file>
getResourceByteString() {
  xxd -p "$1"/..namedfork/rsrc | tr -d '\n'
}

# Patches a single byte in the byte string provided via stdin.
#  patchByteInByteString ndx byteSpec
#   ndx is the 0-based byte index
# - If <byteSpec> has NO prefix: <byteSpec> becomes the new byte
# - If <byteSpec> has prefix '|': "adds" the value: the result of a bitwise OR with the existing byte becomes the new byte
# - If <byteSpec> has prefix '~': "removes" the value: the result of a applying a bitwise AND with the bitwise complement of <byteSpec> to the existing byte becomes the new byte
patchByteInByteString() {
  local ndx=$1 byteSpec=$2 byteVal byteStr charPos op='' charsBefore='' charsAfter='' currByte
  byteStr=$(</dev/stdin)
  charPos=$(( 2 * ndx ))
  # Validat the byte spec.
  case ${byteSpec:0:1} in
    '|')
      op='|'
      byteVal=${byteSpec:1}
      ;;
    '~')
      op='& ~'
      byteVal=${byteSpec:1}
      ;;
    *)
      byteVal=$byteSpec
      ;;
  esac
  [[ $byteVal == [0-9A-Fa-f][0-9A-Fa-f] ]] || return 1
  # Validat the byte index.
  (( charPos > 0 && charPos < ${#byteStr} )) || return 1
  # Determine the target byte, and strings before and after the byte to patch.
  (( charPos >= 2 )) && charsBefore=${byteStr:0:charPos}
  charsAfter=${byteStr:charPos + 2}
  # Determine the new byte value
  if [[ -n $op ]]; then
      currByte=${byteStr:charPos:2}
      printf -v patchedByte '%02X' "$(( 0x${currByte} $op 0x${byteVal} ))"
  else
      patchedByte=$byteSpec
  fi
  printf '%s%s%s' "$charsBefore" "$patchedByte" "$charsAfter"
}

#  hasAttrib <fileOrFolder> <attrib_name>
hasAttrib() {
  xattr "$1" | /usr/bin/grep -Fqx "$2"
}

#  hasIconsResource <file>
hasIconsResource() {
  local file=$1
  getResourceByteString "$file" | /usr/bin/grep -Fq "$kMAGICBYTES_ICNS_RESOURCE"
}


#  setCustomIcon <fileOrFolder> <imgFile>
setCustomIcon() {

  local fileOrFolder=$1 imgFile=$2

  [[ (-f $fileOrFolder || -d $fileOrFolder) && -r $fileOrFolder && -w $fileOrFolder ]] || return 3
  [[ -f $imgFile ]] || return 3

  # !!
  # !! Sadly, Apple decided to remove the `-i` / `--addicon` option from the `sips` utility.
  # !! Therefore, use of *Cocoa* is required, which we do *via Python*, which has the added advantage
  # !! of creating a *set* of icons from the source image, scaling as necessary to create a
  # !! 512 x 512 top resolution icon (whereas sips -i created a single, 128 x 128 icon).
  # !! Thanks, https://apple.stackexchange.com/a/161984/28668
  # !!
  # !! Note: setIcon_forFile_options_() seemingly always indicates True, even with invalid image files, so
  # !!       we attempt no error handling in the Python code.
  /usr/bin/python3 - "$imgFile" "$fileOrFolder" <<'EOF' || return
import Cocoa
import sys

Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_(sys.argv[1]), sys.argv[2], 0)
EOF


  # Verify that a resource fork with icons was actually created.
  # For *files*, the resource fork is embedded in the file itself.
  # For *folders* a hidden file named $'Icon\r' is created *inside the folder*.
  [[ -d $fileOrFolder ]] && fileWithResourceFork=${fileOrFolder}/$kFILENAME_FOLDERCUSTOMICON || fileWithResourceFork=$fileOrFolder
  hasIconsResource "$fileWithResourceFork" || { 
    cat >&2 <<EOF
Failed to create resource fork with icons. Typically, this means that the specified image file is not supported or corrupt: $imgFile
Supported image formats: jpeg | tiff | png | gif | jp2 | pict | bmp | qtif| psd | sgi | tga
EOF
    return 1

  }

  return 0
}

#  getCustomIcon <fileOrFolder> <icnsOutFile>
getCustomIcon() {

  local fileOrFolder=$1 icnsOutFile=$2 byteStr fileWithResourceFork byteOffset byteCount

  [[ (-f $fileOrFolder || -d $fileOrFolder) && -r $fileOrFolder ]] || return 3

  # Determine what file to extract the resource fork from.
  if [[ -d $fileOrFolder ]]; then
    fileWithResourceFork=${fileOrFolder}/$kFILENAME_FOLDERCUSTOMICON
    [[ -f $fileWithResourceFork ]] || { echo "Custom-icon file does not exist: '${fileWithResourceFork/$'\r'/\\r}'" >&2; return 1; }
  else
    fileWithResourceFork=$fileOrFolder
  fi

  # Determine (based on format description at https://en.wikipedia.org/wiki/Apple_Icon_Image_format):
  # - the byte offset at which the icns resource begins, via the magic literal identifying an icns resource
  # - the length of the resource, which is encoded in the 4 bytes right after the magic literal.
  read -r byteOffset byteCount < <(getResourceByteString "$fileWithResourceFork" | /usr/bin/awk -F "$kMAGICBYTES_ICNS_RESOURCE" '{ printf "%s %d", (length($1) + 2) / 2, "0x" substr($2, 0, 8) }')
  (( byteOffset > 0 && byteCount > 0 )) || { echo "Custom-icon file contains no icons resource: '${fileWithResourceFork/$'\r'/\\r}'" >&2; return 1; }

  # Extract the actual bytes using tail and head and save them to the output file.
  tail -c "+${byteOffset}" "$fileWithResourceFork/..namedfork/rsrc" | head -c $byteCount > "$icnsOutFile" || return

  return 0
}

#  removeCustomIcon <fileOrFolder>
removeCustomIcon() {

  local fileOrFolder=$1 byteStr

  [[ (-f $fileOrFolder || -d $fileOrFolder) && -r $fileOrFolder && -w $fileOrFolder ]] || return 1

  # Step 1: Turn off the custom-icon flag in the com.apple.FinderInfo extended attribute.
  if hasAttrib "$fileOrFolder" com.apple.FinderInfo; then
    byteStr=$(getAttribByteString "$fileOrFolder" com.apple.FinderInfo | patchByteInByteString $kFI_BYTEOFFSET_CUSTOMICON '~'$kFI_VAL_CUSTOMICON) || return
    if [[ $byteStr == "$kFI_BYTES_BLANK" ]]; then # All bytes cleared? Remove the entire attribute.
      xattr -d com.apple.FinderInfo "$fileOrFolder"
    else # Update the attribute.
      xattr -wx com.apple.FinderInfo "$byteStr" "$fileOrFolder" || return
    fi
  fi

  # Step 2: Remove the resource fork (if target is a file) / hidden file with custom icon (if target is a folder)
  if [[ -d $fileOrFolder ]]; then
    rm -f "${fileOrFolder}/${kFILENAME_FOLDERCUSTOMICON}"
  else
    if hasIconsResource "$fileOrFolder"; then
      xattr -d com.apple.ResourceFork "$fileOrFolder"
    fi
  fi

  return 0
}

#  testForCustomIcon <fileOrFolder>
testForCustomIcon() {

  local fileOrFolder=$1 byteStr byteVal fileWithResourceFork

  [[ (-f $fileOrFolder || -d $fileOrFolder) && -r $fileOrFolder ]] || return 3

  # Step 1: Check if the com.apple.FinderInfo extended attribute has the custom-icon
  #         flag set.
  byteStr=$(getAttribByteString "$fileOrFolder" com.apple.FinderInfo 2>/dev/null) || return 1

  byteVal=${byteStr:2*kFI_BYTEOFFSET_CUSTOMICON:2}

  (( byteVal & kFI_VAL_CUSTOMICON )) || return 1

  # Step 2: Check if the resource fork of the relevant file contains an icns resource
  if [[ -d $fileOrFolder ]]; then
    fileWithResourceFork=${fileOrFolder}/${kFILENAME_FOLDERCUSTOMICON}
  else
    fileWithResourceFork=$fileOrFolder
  fi

  hasIconsResource "$fileWithResourceFork" || return 1

  return 0
}

# --- End: SPECIFIC HELPER FUNCTIONS

# --- Begin: SPECIFIC SCRIPT-GLOBAL CONSTANTS

kFILENAME_FOLDERCUSTOMICON=$'Icon\r'

# The blank hex dump form (single string of pairs of hex digits) of the 32-byte data structure stored in extended attribute
# com.apple.FinderInfo
kFI_BYTES_BLANK='0000000000000000000000000000000000000000000000000000000000000000'

# The hex dump form of the full 32 bytes that Finder assigns to the hidden $'Icon\r'
# file whose com.apple.ResourceFork extended attribute contains the icon image data for the enclosing folder.
# The first 8 bytes spell out the magic literal 'iconMACS'; they are followed by the invisibility flag, '40' in the 9th byte, and '10' (?? specifying what?)
# in the 10th byte.
# NOTE: Since file $'Icon\r' serves no other purpose than to store the icon, it is
#       safe to simply assign all 32 bytes blindly, without having to worry about
#       preserving existing values.
kFI_BYTES_CUSTOMICONFILEFORFOLDER='69636F6E4D414353401000000000000000000000000000000000000000000000'

# The hex dump form of the magic literal inside a resource fork that marks the
# start of an icns (icons) resource.
# NOTE: This will be used with `xxd -p .. | tr -d '\n'`, which uses *lowercase*
#       hex digits, so we must use lowercase here.
kMAGICBYTES_ICNS_RESOURCE='69636e73'

# The byte values (as hex strings) of the flags at the relevant byte position
# of the com.apple.FinderInfo extended attribute.
kFI_VAL_CUSTOMICON='04'

# The custom-icon-flag byte offset in the com.apple.FinderInfo extended attribute.
kFI_BYTEOFFSET_CUSTOMICON=8

# --- End: SPECIFIC SCRIPT-GLOBAL CONSTANTS

# Option defaults.
force=0 quiet=0

# --- Begin: OPTIONS PARSING
allowOptsAfterOperands=1 operands=() i=0 optName= isLong=0 prefix= optArg= haveOptArgAttached=0 haveOptArgAsNextArg=0 acceptOptArg=0 needOptArg=0
while (( $# )); do
  if [[ $1 =~ ^(-)[a-zA-Z0-9]+.*$ || $1 =~ ^(--)[a-zA-Z0-9]+.*$ ]]; then # an option: either a short option / multiple short options in compressed form or a long option
    prefix=${BASH_REMATCH[1]}; [[ $prefix == '--' ]] && isLong=1 || isLong=0
    for (( i = 1; i < (isLong ? 2 : ${#1}); i++ )); do
        acceptOptArg=0 needOptArg=0 haveOptArgAttached=0 haveOptArgAsNextArg=0 optArgAttached= optArgOpt= optArgReq=
        if (( isLong )); then # long option: parse into name and, if present, argument
          optName=${1:2}
          [[ $optName =~ ^([^=]+)=(.*)$ ]] && { optName=${BASH_REMATCH[1]}; optArgAttached=${BASH_REMATCH[2]}; haveOptArgAttached=1; }
        else # short option: *if* it takes an argument, the rest of the string, if any, is by definition the argument.
          optName=${1:i:1}; optArgAttached=${1:i+1}; (( ${#optArgAttached} >= 1 )) && haveOptArgAttached=1
        fi
        (( haveOptArgAttached )) && optArgOpt=$optArgAttached optArgReq=$optArgAttached || { (( $# > 1 )) && { optArgReq=$2; haveOptArgAsNextArg=1; }; }
        # ---- BEGIN: CUSTOMIZE HERE
        case $optName in
          f|force)
            force=1
            ;;
          q|quiet)
            quiet=1
            ;;
          *)
            dieSyntax "Unknown option: ${prefix}${optName}."
            ;;
        esac
        # ---- END: CUSTOMIZE HERE
        (( needOptArg )) && { (( ! haveOptArgAttached && ! haveOptArgAsNextArg )) && dieSyntax "Option ${prefix}${optName} is missing its argument." || (( haveOptArgAsNextArg )) && shift; }
        (( acceptOptArg || needOptArg )) && break
    done
  else # an operand
    if [[ $1 == '--' ]]; then
      shift; operands+=( "$@" ); break
    elif (( allowOptsAfterOperands )); then
      operands+=( "$1" ) # continue
    else
      operands=( "$@" )
      break
    fi
  fi
  shift
done
(( "${#operands[@]}" > 0 )) && set -- "${operands[@]}"; unset allowOptsAfterOperands operands i optName isLong prefix optArgAttached haveOptArgAttached haveOptArgAsNextArg acceptOptArg needOptArg
# --- End: OPTIONS PARSING: "$@" now contains all operands (non-option arguments).

# Validate the command
cmd=$(printf %s "$1" | tr '[:upper:]' '[:lower:]') # translate to all-lowercase - we don't want the command name to be case-sensitive
[[ $cmd == 'remove' ]] && cmd='rm'  # support alias 'remove' for 'rm'
case $cmd in
  set|get|rm|remove|test)
    shift
    ;;
  *)
    dieSyntax "Unrecognized or missing command: '$cmd'."
    ;;
esac

# Validate file operands
(( $# > 0 )) || dieSyntax "Missing operand(s)."

# Target file or folder.
targetFileOrFolder=$1 imgFile= outFile=
[[ -f $targetFileOrFolder || -d $targetFileOrFolder ]] || die "Target not found or neither file nor folder: '$targetFileOrFolder'"
# Make sure the target file/folder is readable, and, unless only getting or testing for an icon are requested, writeable too.
[[ -r $targetFileOrFolder ]] || die "Cannot access '$targetFileOrFolder': you do not have read permissions."
[[ $cmd == 'test' || $cmd == 'get' || -w $targetFileOrFolder ]] || die "Cannot modify '$targetFileOrFolder': you do not have write permissions."

# Other operands, if any, and their number.
valid=0
case $cmd in
  'set')
    (( $# <= 2 )) && {
      valid=1
      # If no image file was specified, the target file is assumed to be an image file itself whose image should be self-assigned as an icon.
      (( $# == 2 )) && imgFile=$2 || imgFile=$1
      # !! Apparently, a regular file is required - a process subsitution such 
      # !! as `<(base64 -D <encoded-file.txt)` is NOT supported by NSImage.initWithContentsOfFile()
      [[ -f $imgFile && -r $imgFile ]] || die "Image file not found or not a (readable) regular file: $imgFile"
    }
    ;;
  'rm'|'test')
    (( $# == 1 )) && valid=1
    ;;
  'get')
    (( $# == 1 || $# == 2 )) && {
      valid=1
      outFile=$2
      if [[ $outFile == '-' ]]; then
        outFile=/dev/stdout
      else
        # By default, we extract to a file with the same filename root + '.icns'
        # in the current folder.
        [[ -z $outFile ]] && outFile=${targetFileOrFolder##*/}
        # Unless already specified, we append '.icns' to the output filename.
        mustReset=$(shopt -q nocasematch; echo $?); shopt -s nocasematch
        [[ $outFile =~ \.icns$ ]] || outFile+='.icns'
        (( mustReset )) && shopt -u nocasematch
        [[ -e $outFile && $force -eq 0 ]] && die "Output file '$outFile' already exists. To force its replacement, use -f."
      fi
    }
    ;;
esac
(( valid )) || dieSyntax "Unexpected number of operands."

case $cmd in
  'set')
    setCustomIcon "$targetFileOrFolder" "$imgFile" || die
    (( quiet )) || echo "Custom icon assigned to '$targetFileOrFolder' based on '$imgFile'."
    ;;
  'rm')
    removeCustomIcon "$targetFileOrFolder" || die
    (( quiet )) || echo "Custom icon removed from '$targetFileOrFolder'."
    ;;
  'get')
    getCustomIcon "$targetFileOrFolder" "$outFile" || die
    (( quiet )) || { [[ $outFile != '/dev/stdout' ]] && echo "Custom icon extracted to '$outFile'."; }
    exit 0
    ;;
  'test')
    testForCustomIcon "$targetFileOrFolder"
    ec=$?
    (( ec <= 1 )) || die
    if (( ! quiet )); then
      (( ec == 0 )) && echo "HAS custom icon: '$targetFileOrFolder'" || echo "Has NO custom icon: '$targetFileOrFolder'"
    fi
    exit $ec
    ;;
  *)
    die "DESIGN ERROR: unanticipated command: $cmd"
    ;;
esac

exit 0

####
# MAN PAGE MARKDOWN SOURCE
#  - Place a Markdown-formatted version of the man page for this script
#    inside the here-document below.
#    The document must be formatted to look good in all 3 viewing scenarios:
#     - as a man page, after conversion to ROFF with marked-man
#     - as plain text (raw Markdown source)
#     - as HTML (rendered Markdown)
#  Markdown formatting tips:
#   - GENERAL
#     To support plain-text rendering in the terminal, limit all lines to 80 chars.,
#     and, for similar rendering as HTML, *end every line with 2 trailing spaces*.
#   - HEADINGS
#     - For better plain-text rendering, leave an empty line after a heading
#       marked-man will remove it from the ROFF version.
#     - The first heading must be a level-1 heading containing the utility
#       name and very brief description; append the manual-section number
#       directly to the CLI name; e.g.:
#         # foo(1) - does bar
#     - The 2nd, level-2 heading must be '## SYNOPSIS' and the chapter's body
#       must render reasonably as plain text, because it is printed to stdout
#       when  `-h`, `--help` is specified:
#         Use 4-space indentation without markup for both the syntax line and the
#         block of brief option descriptions; represent option-arguments and operands
#         in angle brackets; e.g., '<foo>'
#     - All other headings should be level-2 headings in ALL-CAPS.
#   - TEXT
#      - Use NO indentation for regular chapter text; if you do, it will
#        be indented further than list items.
#      - Use 4-space indentation, as usual, for code blocks.
#      - Markup character-styling markup translates to ROFF rendering as follows:
#         `...` and **...** render as bolded (red) text
#         _..._ and *...* render as word-individually underlined text
#   - LISTS
#      - Indent list items by 2 spaces for better plain-text viewing, but note
#        that the ROFF generated by marked-man still renders them unindented.
#      - End every list item (bullet point) itself with 2 trailing spaces too so
#        that it renders on its own line.
#      - Avoid associating more than 1 paragraph with a list item, if possible,
#        because it requires the following trick, which hampers plain-text readability:
#        Use '&nbsp;<space><space>' in lieu of an empty line.
####
: <<'EOF_MAN_PAGE'
# fileicon(1) - manage file and folder custom icons

## SYNOPSIS

Manage custom icons for files and folders on macOS.  

SET a custom icon for a file or folder:

    fileicon set      <fileOrFolder> [<imageFile>]

REMOVE a custom icon from a file or folder:

    fileicon rm       <fileOrFolder>

GET a file or folder's custom icon:

    fileicon get [-f] <fileOrFolder> [<iconOutputFile>]

    -f ... force replacement of existing output file

TEST if a file or folder has a custom icon:

    fileicon test     <fileOrFolder>

All forms: option -q silences status output.

Standard options: `--help`, `--man`, `--version`, `--home`

## DESCRIPTION

`<fileOrFolder>` is the file or folder whose custom icon should be managed.  
Note that symlinks are followed to their (ultimate target); that is, you  
can only assign custom icons to regular files and folders, not to symlinks  
to them.

`<imageFile>` can be an image file of any format supported by the system.  
It is converted to an icon and assigned to `<fileOrFolder>`.  
If you omit `<imageFile>`, `<fileOrFolder>` must itself be an image file whose
image should become its own icon.

`<iconOutputFile>` specifies the file to extract the custom icon to:  
Defaults to the filename of `<fileOrFolder>` with extension `.icns` appended.  
If a value is specified, extension `.icns` is appended, unless already present.  
Either way, extraction fails if the target file already exists; use `-f` to  
override.  
Specify `-` to extract to stdout.  

Command `test` signals with its exit code whether a custom icon is set (0)  
or not (1); any other exit code signals an unexpected error.

**Options**:

  * `-f`, `--force`  
    When getting (extracting) a custom icon, forces replacement of the  
    output file, if it already exists.

  * `-q`, `--quiet`  
    Suppresses output of the status information that is by default output to  
    stdout.  
    Note that errors and warnings are still printed to stderr.

## NOTES

Custom icons are stored in extended attributes of the HFS+ filesystem.  
Thus, if you copy files or folders to a different filesystem that doesn't  
support such attributes, custom icons are lost; for instance, custom icons  
cannot be stored in a Git repository.

To determine if a give file or folder has extended attributes, use  
`ls -l@ <fileOrFolder>`.

When setting an image as a custom icon, a set of icons with several resolutions  
is created, with the highest resolution at 512 x 512 pixels.

All icons created are square, so images with a non-square aspect ratio will  
appear distorted; for best results, use square imges.

## STANDARD OPTIONS

All standard options provide information only.

* `-h, --help`  
  Prints the contents of the synopsis chapter to stdout for quick reference.

* `--man`  
  Displays this manual page, which is a helpful alternative to using `man`, 
  if the manual page isn't installed.

* `--version`  
  Prints version information.
  
* `--home`  
  Opens this utility's home page in the system's default web browser.

## LICENSE

For license information and more, visit the home page by running  
`fileicon --home`

EOF_MAN_PAGE
