param(
    [string]$Python,
    [ValidateRange(1, 65535)]
    [int]$Puerto = 8001,
    [ValidateRange(1, 65535)]
    [int]$PuertoMySQL = 3306,
    [ValidateSet('keywords', 'embeddings', 'zeroshot')]
    [string]$Modelo = 'keywords'
)

$ErrorActionPreference = 'Stop'
$proyecto = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$origen = "http://127.0.0.1:$Puerto"
$urlDashboard = "$origen/src/options/options.html"
$direccion = [System.Net.IPAddress]::Loopback
$pruebaPuerto = [System.Net.Sockets.TcpListener]::new($direccion, $Puerto)
$pruebaPuerto.ExclusiveAddressUse = $true
try {
    $pruebaPuerto.Start()
} catch {
    if ($_.Exception.InnerException -is [System.Net.Sockets.SocketException] -and
        $_.Exception.InnerException.SocketErrorCode -eq [System.Net.Sockets.SocketError]::AddressAlreadyInUse) {
        $dashboardActivo = $false
        try {
            $salud = Invoke-RestMethod "$origen/api/salud" -TimeoutSec 2
            $pagina = Invoke-WebRequest $urlDashboard -UseBasicParsing -TimeoutSec 2
            $dashboardActivo = $salud.listo -eq $true -and
                $pagina.Content.Contains('id="formAcceso"')
        } catch {
            # El puerto puede pertenecer a otro servicio.
        }
        if ($dashboardActivo) {
            Write-Host "ModerAI ya esta abierto en $urlDashboard (modo $($salud.modelo))"
            if ($salud.modelo -ne $Modelo) {
                Write-Host "Deten la instancia actual antes de cambiar al modo $Modelo."
            }
            return
        }
        throw "Otro servicio ocupa el puerto $Puerto. Elige otro con -Puerto."
    }
    throw
} finally {
    $pruebaPuerto.Stop()
}
$entornoPython = Join-Path $proyecto '.venv\Scripts\python.exe'
if (-not $Python) {
    $Python = if (Test-Path -LiteralPath $entornoPython -PathType Leaf) { $entornoPython } else { 'python' }
}
$interprete = Get-Command $Python -CommandType Application -ErrorAction Stop
& $interprete.Source -c 'import fastapi, uvicorn, argon2, mysql.connector' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'El entorno Python del dashboard no funciona. Recrea .venv con tu instalacion local de Python e instala las dependencias de la guia.'
}
if ($Modelo -ne 'keywords') {
    & $interprete.Source -c 'import torch, transformers, sentence_transformers' 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Faltan las dependencias del modelo. Instala api/requirements.txt en el entorno Python de ModerAI.'
    }
}
$configLocal = Join-Path $env:LOCALAPPDATA 'ModerAI'
$archivoClave = Join-Path $configLocal 'dashboard-password.txt'
$credencial = Join-Path $configLocal 'dashboard-mysql.dpapi'
$clave = $null
$textoClave = $null
$hostMySQL = '127.0.0.1'
$usuarioMySQL = 'moderai_dashboard'
$certificadoMySQL = $null

function Leer-AjusteMySQL($ajustes, [string[]]$nombres) {
    foreach ($nombre in $nombres) {
        if ($ajustes.ContainsKey($nombre)) { return [string]$ajustes[$nombre] }
    }
}

$conexionVisualStudio = $null
$archivoProyecto = Join-Path $proyecto 'ModerAI.Web\ModerAI.Web.csproj'
if ($env:APPDATA -and (Test-Path -LiteralPath $archivoProyecto -PathType Leaf)) {
    $proyectoWeb = [xml](Get-Content -LiteralPath $archivoProyecto -Raw)
    $idSecretos = [string]$proyectoWeb.Project.PropertyGroup.UserSecretsId
    if ($idSecretos) {
        $archivoSecretos = Join-Path $env:APPDATA "Microsoft\UserSecrets\$idSecretos\secrets.json"
        if (Test-Path -LiteralPath $archivoSecretos -PathType Leaf) {
            try {
                $secretos = Get-Content -LiteralPath $archivoSecretos -Raw | ConvertFrom-Json
                $conexionVisualStudio = $secretos.'ConnectionStrings:ModerAI'
                if (-not $conexionVisualStudio) { $conexionVisualStudio = $secretos.ConnectionStrings.ModerAI }
            } catch {
                throw 'El archivo de secretos de ModerAI.Web no tiene un formato JSON válido.'
            }
        }
    }
}

if ($conexionVisualStudio) {
    try {
        $ajustes = [System.Data.Common.DbConnectionStringBuilder]::new()
        $ajustes.set_ConnectionString($conexionVisualStudio)
    } catch {
        throw 'Revisa el formato de ConnectionStrings:ModerAI en User Secrets.'
    }
    $hostMySQL = Leer-AjusteMySQL $ajustes @('Server', 'Host', 'Data Source', 'Address', 'Addr', 'Network Address')
    if ($hostMySQL -eq 'localhost') { $hostMySQL = '127.0.0.1' }
    $usuarioMySQL = Leer-AjusteMySQL $ajustes @('User ID', 'UserID', 'UID', 'User', 'Username', 'User Name')
    $textoClave = Leer-AjusteMySQL $ajustes @('Password', 'Pwd')
    $baseMySQL = Leer-AjusteMySQL $ajustes @('Database', 'Initial Catalog')
    $modoTLS = Leer-AjusteMySQL $ajustes @('SslMode', 'SSL Mode')
    $certificadoMySQL = Leer-AjusteMySQL $ajustes @('SslCa', 'SSL CA', 'Ssl-Ca')
    $puertoConfigurado = Leer-AjusteMySQL $ajustes @('Port')
    if ($puertoConfigurado -and -not $PSBoundParameters.ContainsKey('PuertoMySQL')) {
        if ($puertoConfigurado -notmatch '^\d{1,5}$' -or [int]$puertoConfigurado -lt 1 -or [int]$puertoConfigurado -gt 65535) {
            throw 'El puerto MySQL de User Secrets debe estar entre 1 y 65535.'
        }
        $PuertoMySQL = [int]$puertoConfigurado
    }
    if (-not $hostMySQL -or -not $usuarioMySQL -or $usuarioMySQL -eq 'root' -or -not $textoClave -or
        $baseMySQL -ne 'moderai_usuarios') {
        throw 'Configura ConnectionStrings:ModerAI con una cuenta dedicada para moderai_usuarios.'
    }
    if ($modoTLS -eq 'VerifyFull') {
        if (-not $certificadoMySQL) { $certificadoMySQL = $env:ACCOUNTS_DB_SSL_CA }
        if (-not $certificadoMySQL -or -not (Test-Path -LiteralPath $certificadoMySQL -PathType Leaf)) {
            throw 'MySQL con VerifyFull requiere un certificado CA accesible para FastAPI.'
        }
    } elseif ($hostMySQL -ne '127.0.0.1' -or $modoTLS -ne 'Required') {
        throw 'Usa TLS Required para MySQL local o VerifyFull con un certificado CA.'
    }
    $secretos = $null
    $conexionVisualStudio = $null
    $ajustes.Clear()
    Write-Host 'MySQL configurado desde User Secrets de ModerAI.Web.'
} elseif (Test-Path -LiteralPath $archivoClave -PathType Leaf) {
    $textoClave = [System.IO.File]::ReadAllText($archivoClave).TrimEnd("`r", "`n")
    if (-not $textoClave) {
        throw "Escribe la contrasena de moderai_dashboard en $archivoClave y vuelve a iniciar."
    }
    if ($textoClave.Contains("`r") -or $textoClave.Contains("`n")) {
        throw 'El archivo dashboard-password.txt debe contener solo una linea.'
    }
} elseif (Test-Path -LiteralPath $credencial -PathType Leaf) {
    $clave = (Get-Content -LiteralPath $credencial -Raw).Trim() | ConvertTo-SecureString
} else {
    $clave = Read-Host 'Contrasena de MySQL para moderai_dashboard' -AsSecureString
}
if ($null -ne $clave -and $clave.Length -eq 0) {
    $clave.Dispose()
    throw 'Se requiere la contrasena de la cuenta dedicada.'
}

$api = [System.Diagnostics.ProcessStartInfo]::new()
$api.FileName = $interprete.Source
$api.Arguments = "-m uvicorn api.main:app --host 127.0.0.1 --port $Puerto"
$api.WorkingDirectory = $proyecto
$api.UseShellExecute = $false
$api.EnvironmentVariables['ACCOUNTS_DB_HOST'] = $hostMySQL
$api.EnvironmentVariables['ACCOUNTS_DB_PORT'] = "$PuertoMySQL"
$api.EnvironmentVariables['ACCOUNTS_DB_USER'] = $usuarioMySQL
if ($certificadoMySQL) { $api.EnvironmentVariables['ACCOUNTS_DB_SSL_CA'] = $certificadoMySQL }
$api.EnvironmentVariables['MODERAI_MODELO'] = $Modelo

$clavePtr = [IntPtr]::Zero
try {
    if ($null -ne $clave) {
        $clavePtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clave)
        $textoClave = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($clavePtr)
    }
    $api.EnvironmentVariables['ACCOUNTS_DB_PASSWORD'] = $textoClave
    $textoClave = $null
    Write-Host "Dashboard en $urlDashboard"
    $proceso = [System.Diagnostics.Process]::Start($api)
} finally {
    $api.EnvironmentVariables.Remove('ACCOUNTS_DB_PASSWORD')
    if ($clavePtr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($clavePtr)
    }
    if ($null -ne $clave) {
        $clave.Dispose()
    }
}
try {
    $proceso.WaitForExit()
    if ($proceso.ExitCode -ne 0) {
        throw "FastAPI termino con codigo $($proceso.ExitCode)."
    }
} finally {
    $proceso.Dispose()
}
