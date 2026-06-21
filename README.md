# YTweaks

Working features:
- **Fullscreen to the right or left**: Locks fullscreen orientation.
- **Night Mode**: Lowers brightness below device minimum by "faking it" with an app-wide semi-transparent black overlay. Works best on OLED devices.
- **Disable floating miniplayer**: Restores the old miniplayer by disabling the floating miniplayer.
- **Virtual fullscreen bezels**: Adds invisible touch-safe zones on black bars to prevent accidental taps and skips.
- **Fix Casting** - Attempts to fix casting by changing some A/B flags. Only works on v20.10.4 or lower.
- **Hide AI Summaries**: Hides AI-generated summaries below videos in the home feed. 

**Note on AI Summaries**: This setting is a work in progress. The space taken up by summaries still remains. It may take multiple app restarts for the setting to stick initially.

More settings will most likely be added in the future. Designed to work with a [fork of YTLite](https://github.com/fosterbarnes/YTPlusYTweaks/) (also known as [YouTube Plus](https://github.com/dayanch96/YTLite)).

<table>
   <tr>
      <td><img src="https://raw.githubusercontent.com/fosterbarnes/YTPlusYTweaks/main/Resources/scr13.jpg" alt="Screenshot 1" width="250" /></td>
   </tr>
</table>

## Building 
Refer to [YTPlusYTweaks](https://github.com/fosterbarnes/YTPlusYTweaks#how-to-build-a-ytplusytweaks-app) for build info

## Supported YouTube versions

20.10.4 is recommended. 'Fix Casting' and 'Disable floating miniplayer' settings do not yet work on newer versions.

**Latest confirmed:** 21.24.3

**Date tested:** 1/17/2026
## Special Thanks

Thanks to PoomSmart for making the various tweaks that made this possible. This tweak is essentially a stripped down fork of https://github.com/PoomSmart/YTABConfig
