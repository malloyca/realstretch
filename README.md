# realstretch
Realtime implementation of the Paulstretch audio time-stretch algorithm using a novel buffer management technique

### Prerequisites
- Matlab
  - DSP System Toolbox
  - Audio Toolbox
  
These are available from [MathWorks](https://www.mathworks.com/products/matlab.html).

### Pre-compiled plugins
Pre-compiled versions of the plugin are available here:
* MacOS:
  * [AudioUnit](https://github.com/malloyca/realstretch/releases/download/v1.0.0/realstretch-macos.component.zip) (stereo only)
  * [VST](https://github.com/malloyca/realstretch/releases/download/v1.0.0/realstretch-macos.vst.zip) (stereo only)
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
