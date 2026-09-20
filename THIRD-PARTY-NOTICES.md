# Third-party notices

## Olaf Hartong Sysmon Modular configurations

The files in `config/vendor/` are verbatim, SHA-256-locked copies of the generated configuration assets identified in `config/sysmon-modular-release.json` from [olafhartong/sysmon-modular](https://github.com/olafhartong/sysmon-modular). The notice below is the upstream `license.md` text at the [release commit](https://raw.githubusercontent.com/olafhartong/sysmon-modular/082cba578667a5f57b44a8e64bc02548d2338859/license.md) and the [MDE configuration commit](https://raw.githubusercontent.com/olafhartong/sysmon-modular/34b8db3e7e06ad45eb4c4b13da67b333eabe8343/license.md).

Licensed under the MIT License:

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Microsoft Sysmon

This project does not redistribute a Sysmon executable. Endpoint scripts use the optional built-in Windows Sysmon feature. The standalone Sysinternals Sysmon terms prohibit third-party publication of that software; see the Microsoft Sysinternals Software License Terms and Licensing FAQ.

## Microsoft Intune PowerShell SDK upload sample

`scripts/Deploy-IntuneAmaApplication.ps1` independently implements the `ProfileVersion1` content-encryption layout and bounded upload flow using the [Microsoft Intune PowerShell SDK UploadLobApp sample](https://github.com/microsoft/Intune-PowerShell-SDK/blob/master/Samples/Apps/UploadLobApp.psm1) as a behavioral reference. The sample is licensed under the MIT License, Copyright (c) Microsoft Corporation.
