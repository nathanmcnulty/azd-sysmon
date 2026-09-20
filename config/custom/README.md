# Custom Sysmon configurations

Place one or more complete Sysmon configuration XML files in this folder, or point the package builder at another folder with `-CustomConfigurationFolder`.

Each top-level `.xml` file becomes a configuration choice using its filename stem as the key. Use letters, numbers, and hyphens, beginning with a letter or number; the key is normalized to lowercase. For example, `workstation.xml` becomes the `workstation` choice.

When `-CustomConfigurationFolder` is supplied, the custom XML files replace Olaf Hartong’s packaged configurations for that build. Olaf’s XML files are not downloaded or included. The files must contain a `Sysmon` root and an `EventFiltering` element.

Example:

```powershell
pwsh -File .\scripts\Build-SysmonPackages.ps1 `
    -CustomConfigurationFolder .\config\custom `
    -DefaultConfiguration workstation

azd env set AZD_SYSMON_CONFIG workstation
azd up
```

The generated package manifest records the custom configuration keys and SHA-256 hashes. The builder fails if the generated Intune scripts reach 200 KB; reduce the number or size of custom XML files if that occurs.
