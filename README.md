# Potlatch

Potlatch is an intermediate-level editor for OpenStreetMap. It's simple to use with numerous powerful features.

From 2010 to 2020, Potlatch (version 2) was available as an online editor on openstreetmap.org via the Flash Player. Version 3 is a port to run under the desktop AIR environment. Potlatch will run on Mac and Windows as a standalone app or using the AIR runtime; Linux compatibility is under investigation.

If you just want to run Potlatch, go to https://www.systemed.net/potlatch/download/ . This repository is for people interested in developing it, and for reporting issues.

## Building Potlatch

To install the AIR tools for development:

* Download the Apache Flex SDK: https://flex.apache.org/installer.html
* Download the Adobe/Harman AIR SDK: https://airsdk.harman.com/download
* Copy the AIR files over the Flex files, so that the result is a combined AIR/Flex directory

Add the /bin subdirectory to your PATH so that you can find the build tools (for example, `export PATH="/Users/richard/Code/Flex/bin:$PATH"`).

Then to compile Potlatch:

`amxmlc potlatch2.mxml -debug=false -omit-trace-statements=false -swf-version=11`

And to run it:

`adl potlatch2-app.xml -nodebug`

(Adjust the various debug flags accordingly!)

## Known issues with v3

* Running Potlatch on Linux is not yet established (other than via the Wine emulation environment).
* Localisation is not currently integrated into the build process.
* Many artefacts of online deployment still need to be cleaned up.

Thanks to Dave Stubbs, Andy Allan, Steve Bennett and everyone else who contributed to Potlatch over the years. 

Richard Fairhurst / @richardf
