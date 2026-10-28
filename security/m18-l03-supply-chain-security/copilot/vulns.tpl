{{- range . }}{{ range .Vulnerabilities }}{{ printf "%-10s %-10s %-20s %-9s fixed in %s\n" .PkgName .InstalledVersion .VulnerabilityID .Severity .FixedVersion }}{{ end }}{{ end -}}
