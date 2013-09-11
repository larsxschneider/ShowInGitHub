# Show in GitHub / BitBucket
Xcode plugin to open a related Github or BitBucket page directly form the Xcode editor code window.

Click [here](https://www.youtube.com/watch?v=dWRjkYk8A6s) for a tutorial. In addition I presented the tool on [Git Merge 2013 in Berlin](https://www.youtube.com/watch?v=nmSFRKfFMak).


* [Open a Github page with the commit of the current Xcode editor line to make a comment on Github](https://github.com/larsxschneider/ShowInGitHub/commit/2149a9b4944770c2f1430761cc13abee6fa8bbe5#L0R190) ![Screenshot](https://raw.github.com/larsxschneider/ShowInGitHub/master/open_commit_example.png))


* [Open a Github page with the last commit and mark the currently selected lines (e.g. to send this URL via IM)](https://github.com/larsxschneider/ShowInGitHub/blob/48a2316b918eb540e1ed8d852fed523f927d40af/Source/Classes/SIGPlugin.m#L199-210)![Screenshot](https://raw.github.com/larsxschneider/ShowInGitHub/master/open_file_example.png))

Show in GitHub was developed and tested with Xcode 4.5.

## Usage

0. Install it via [Alcatraz](http://mneorr.github.io/Alcatraz/)

or

1. Clone the repo on your local machine.

2. Build it.

3. `ShowInGitHub.xcplugin` should appear in `~/Library/Application Support/Developer/Shared/Xcode/Plug-ins

3. Restart Xcode

4. Click on any line in a GitHub project and choose "GitHub" --> "Show in GitHub" in the main menu


## Contact

Lars Schneider <larsxschneider+sig@gmail.com>


## License

Show in GitHub is available under the BSD license. See the LICENSE file for more info.
