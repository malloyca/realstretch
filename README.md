# realstretch
Realtime implementation of the Paulstretch audio time-stretch algorithm using a novel buffer management technique

### Prerequisites
* This project is coded in Matlab using the audio toolbox.
The Matlab software and audio toolbox are required to edit and compile the project.
They are available from [MathWorks](https://www.mathworks.com/products/matlab.html).

### Pre-compiled plugins
Pre-compiled versions of the plugin are available here:
* MacOS:
  * [AudioUnit](https://github.com/malloyca/realstretch/releases/download/v0.1.3/macos-realstretch.component.zip) (stereo only)
  * [VST](https://github.com/malloyca/realstretch/releases/download/v0.1.3/macos-realstretch.vst.zip) (stereo only)
* Windows:
  * Coming soon.

Mono versions of the plugins are also coming soon.

### Installation instructions
#### MacOS
- Unzip the AU and VST files.
- Open the finder and go to the home folder.
- Then go to <code>/Library/Audio/Plug-Ins/</code>
- Place <code>macos-realstretch.component</code> in the <code>/Components/</code> folder and <code>macos-realstretch.vst</code> in the <code>/VST/</code> folder.

### Paulstretch
This project is based on the Paulstretch algorithm.
If you are interested in that project there are GitHub pages for:
* The original [C++](https://github.com/paulnasca/paulstretch_cpp) version and...
* The [Python](https://github.com/paulnasca/paulstretch_python) version.
