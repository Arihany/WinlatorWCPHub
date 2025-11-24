<p align="center">
  <img src="./img.png" width="220">
</p>

<h3 align="center">Winlator WCP Hub</h3>
<h4 align="center">Transparent builds, always up to date</h4>

---

> [!TIP]
> <details>
>  <summary><b>What does this hub do?</b></summary><br>
>
> **Winlator WCP Hub** uses an open, automated build pipeline to distribute essential WCP packages along with some useful details. Honestly, I mostly made it for my own peace of mind. 😌
>  
> ---
> 
> </details>
> <details>
>  <summary><b>What exactly is Winlator-Bionic?</b></summary><br>
>
> ### Winlator is an Android app created by [brunodev85](https://github.com/brunodev85). 
>  
> It runs Windows software inside a glibc-based environment built around Wine and Box64. It follows a conservative, tightly integrated design that favors stability and predictable performance over aggressive experimentation.
>
> ---
>
> ### Winlator-Bionic is a community fork based on [Pipetto-crypto](https://github.com/Pipetto-crypto)’s project.
>
> It runs closer to Android’s native stack, using a more direct Vulkan path that can reduce overhead and improve performance on many devices. It supports both Box64 and FEXCore/Arm64EC containers and lets users mix and match components such as Wine builds and graphics layers through modular WCP packages. The project actively experiments with new features and configurations.
> 
> --- 
>
> | Bionic builds | 📝 |
> |:-:|-|
> | [**Winlator-CMod**](https://github.com/coffincolors/winlator/releases) | Baseline Bionic build with excellent controller support. |
> | [**Winlator-Ludashi**](https://github.com/StevenMXZ/Winlator-Ludashi/releases) | Keeps up with the latest upstream code while remaining close to vanilla. |
> | [**Winlator-OSS**](https://github.com/Mart-01-oss/WinlatorOSS/releases) | Keeps up with the latest upstream code, combines CMod features with additional QoL improvements. |
> 
> - Somewhere deeper in this rabbit hole, even stranger forks exist, but they’re out of scope here.
>
> </details>

---

### 🌀 FEXCore & Box64

| Type | 📦 | 🏷️ | 📜 |
|:-:|:-:|:-:|:-:|
| FEXCore | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/FEXCore-Nightly) | <!--fex--> `2511`|<a href="https://github.com/FEX-Emu/FEX/releases">🔗</a> |
| Box64-Bionic | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-BIONIC-NIGHTLY) | <!--box64--> `0.3.8` `0.3.9`| <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
| WowBox64 | [**`Stable`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WOWBOX64) [**`Nightly`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/WOWBOX64-NIGHTLY) | <!--box64--> `0.3.8` `0.3.9`| <a href="https://github.com/ptitSeb/box64/releases">🔗</a> |
<!--| Box64-Glibc | [**Stable**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-STABLE) &nbsp; [**Nightly**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/BOX64-NIGHTLY) | Paused ||-->

<details>
<summary>💡Quick Info</summary>
<br>

| Type | 📝 |
|:-:|-|
| **FEXCore** | Focuses on accuracy and modern titles, offering strong compatibility and stable behavior for demanding games. It’s best to use the latest Bionic build. |
| **Box64** | Known for its speed and flexibility. Great for older titles or for squeezing extra performance out of specific hardware through extensive dynarec tuning. |
| **WowBox64** | A 32-bit x86 Windows guest library that is loaded inside the Wine environment, thunking 32-bit Windows API calls to the 64-bit host. |

---

</details>

<details>
<summary>🧐 UNITY SETTINGS</summary>

---

### 🧠 Unity scripting backends

| Backend | 🔍 | 📝 |
|:-:|:-:|-|
| **Old Mono** | `UnityEngine.dll` | ❌ Very cumbersome, and even when it runs the performance drop is severe. |
| **Mono** | `Assembly-CSharp.dll` | 🟡 Used by most Unity games. Performance varies, but it generally runs. |
| **IL2CPP** | `GameAssembly.dll` | 🟢 Performs well and usually tolerates more aggressive settings without issues. |

---

### ⚙️ General Modern Mono+ Settings

| Box64 | 🏷️ | 📝 |
|:-:|:-:|-|
| **SAFEFLAGS** | `1` | Keep as is. Higher values are usually too slow to be worth it. |
| **STRONGMEM** | `1` | Required for many Unity games. Higher values are usually too slow to be worth it. |
| **WEAKBARRIER** | `1` | Reduces the performance cost of `STRONGMEM`. Set to `0` if the game crashes. |
| **BIGBLOCK** | `2` | Lower values are more stable. Official recommendation is `0` but `2` is usually still safe. |
| **CALLRET** | `0` | `1` might help performance, but the gain is modest. |
| **WAIT** | `1` | `0` can improve performance but may cause instability. |
| **DIRTY** | `0` | Keep as is. |
| **MMAP32** | `1` | Good for performance. Set to `0` only if it clearly causes issues. |

| FEXCore | 🏷️ | 📝 |
|:-:|:-:|-|
| **TSOEnabled** | `1` | Required for many Unity games. You can test `0` to improve performance. |
| **HalfBarrierTSOEnabled** | `1` | Keep enabled for correctness. Set to `0` only for experimental performance tuning. |
| **Multiblock** | `0` | Set to `1` only if the game is already stable and you want more performance. |
| **SMCChecks** | `MTrack` | Keep as is. Higher values are usually too slow to be worth it. |
| **X87ReducedPrecision** | `1` | Set to `0` for older titles or if subtle bugs occur. |

</details>

---

### ⚡ DXVK (DX9-11) & VKD3D (DX12)

| 📦 | 🏷️ | 📜 |
|-|:-:|:-:|
| [**`DXVK`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-ARM64EC) | <!--dxvk--> `2.7.1`| <a href="https://github.com/doitsujin/dxvk/releases">🔗</a> |
| [**`DXVK-gplasync`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-GPLASYNC-ARM64EC)| <!--gplasync--> `2.7.1-1`| <a href="https://gitlab.com/Ph42oN/dxvk-gplasync/-/releases">🔗</a> |
| [**`DXVK-Sarek-async`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/DXVK-SAREK-ASYNC-ARM64EC) | <!--sarek--> `1.11.0`| <a href="https://github.com/pythonlover02/DXVK-Sarek/releases">🔗</a> |
| [**`VKD3D-Proton`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON) [**`Arm64EC`**](https://github.com/Arihany/WinlatorWCPHub/releases/tag/VKD3D-PROTON-ARM64EC) | <!--vkd3d--> `3.0a`|<a href="https://github.com/HansKristian-Work/vkd3d-proton/releases">🔗</a> |

<details>
  <summary>💡Quick Info</summary>
<br> 

| Type | 📝 |
|:-:|-|
| **Sarek**    | A modernized fork of DXVK `1.10.x` with backported fixes to keep older GPUs with weaker Vulkan support more stable. If you’re still on `1.10.x`, this is a good one to try. |
| **gplasync** | `gpl` cache + `async` shader compilation to smooth out shader hitches and visible stutter. |
| **Arm64EC**  | Designed to be paired with `FEXCore` to cut down translation work and keep overhead lower. |

- Running the very latest version isn’t always an improvement.

</details>

---
<br><br>
<p align="center">
  <img src="./img2.png" width="100">
</p>
<h3 align="center">Additional Packages and Helpful Links</h3>

---

### 🔥 Adreno Driver
| Link | 📝 |
|:-:|-|
| [**K11MCH1**](https://github.com/K11MCH1/AdrenoToolsDrivers) | Qualcomm driver for Elite (a8xx), Mesa turnip driver for a6xx - a7xx. |
| [**GameNative**](https://gamenative.app/drivers/) | Qualcomm driver for Elite (a8xx), Mesa turnip driver for a6xx - a7xx. |
| [**zoerakk**](https://github.com/zoerakk/qualcomm-adreno-driver) | Qualcomm driver for Elite (a8xx). |


<details>
  <summary>💡Quick Info</summary>
<br> 
  
| Type | 📝 |
|:-:|-|
| **Qualcomm driver** | Extracted from the official Adreno driver of a recent device. Partially compatible with similar chipsets. Emulation may show reduced performance or rendering glitches. |
| **Mesa turnip driver** | Open source Mesa driver with broader Vulkan support and emulator friendly behavior. Often more compatible or stable across devices. |

</details>

---

### 📦 Runtime Packages

| Type | 📝 |
|-|-|
| [**Visual C++ x64**](https://aka.ms/vs/17/release/vc_redist.x64.exe) | 2015–2022 Redistributable |
| [**Visual C++ x86**](https://aka.ms/vs/17/release/vc_redist.x86.exe) | 2015–2022 Redistributable |
| [**Visual C++ ARM64**](https://aka.ms/vs/17/release/vc_redist.arm64.exe) | 2015–2022 Redistributable |
| [**Wine-Mono (*.msi)**](https://github.com/wine-mono/wine-mono/releases) | .NET runtime for Wine (**Install only when the built-in tool is not working**) |
| [**Wine-Gecko (*.msi)**](https://dl.winehq.org/wine/wine-gecko/) | HTML engine for Wine (**Install only when the built-in tool is not working**) |
| [**DirectX (June 2010)**](https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe) | **Install only if missing Legacy DirectX DLL** |
| [**PhysX Legacy**](https://www.nvidia.com/content/DriverDownload-March2009/confirmation.php?url=/Windows/9.13.0604/PhysX-9.13.0604-SystemSoftware-Legacy.msi&lang=us&type=Other) | **Install only if an old game requests PhysX DLL** |
| [**XNA Framework**](https://download.microsoft.com/download/a/c/2/ac2c903b-e6e8-42c2-9fd7-bebac362a930/xnafx40_redist.msi) | xna40. Old indie games runtime |

<details>
  <summary>💡Quick Info</summary>
<br>

- Install only the minimum necessary.
- If older VC++ is needed, try an [**AIO package**](https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/). <br>

</details>

---

### 🌐 More Repos
[**Winlator 101**](https://github.com/K11MCH1/Winlator101)

---
<br>
<h3 align="center"> Credits </h3>
<h4 align="center">
Third-party components used for packaging (such as DXVK, Wine, vkd3d-proton, FEX, etc.) retain their original upstream licenses.
WCP packages redistribute unmodified (or minimally patched) binaries, and all copyrights and credits belong to the original authors.
<br><br>

FEX [Billy Laws](https://github.com/bylaws)<br>
Box64 [ptitSeb](https://github.com/ptitSeb)<br>
DXVK [Philip Rebohle](https://github.com/doitsujin)<br>
DXVK-Sarek [pythonlover02](https://github.com/pythonlover02)<br>
DXVK-GPLAsync Patch [Ph42oN](https://gitlab.com/Ph42oN)<br>
VKD3D [Hans-Kristian Arntzen](https://github.com/HansKristian-Work)<br>

</h4>

