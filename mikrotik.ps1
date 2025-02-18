# Необходим для быстрой корректировки формата
class log {
    static message([string] $msg, [bool] $newline) { [log]::echo($msg, [ConsoleColor]::Gray,   $newline) }
    static info(   [string] $msg, [bool] $newline) { [log]::echo($msg, [ConsoleColor]::Yellow, $newline) }
    static warning([string] $msg, [bool] $newline) { [log]::echo($msg, [ConsoleColor]::Red,    $newline) }
    static success([string] $msg, [bool] $newline) { [log]::echo($msg, [ConsoleColor]::Green,  $newline) }

    static message([string] $msg) { [log]::message($msg, $true) }
    static info(   [string] $msg) { [log]::info(   $msg, $true) }
    static warning([string] $msg) { [log]::warning($msg, $true) }
    static success([string] $msg) { [log]::success($msg, $true) }

    hidden static echo([string] $msg, [ConsoleColor] $type, [bool] $newline) {
        if ($newline) { 
            Write-Host ("{0}" -f $msg) -ForegroundColor $type 
        } else { 
            Write-Host ("{0}" -f $msg) -ForegroundColor $type -NoNewline
        }
    }
}

# Функция обрабатывает пользовательский ввод для SecureString
function readUserInputSecure {
    param ([string] $message)
    return $(Read-Host ("> {0}" -f $message) -AsSecureString)
}

# Функция обрабатывает пользовательский ввод для Plain text
function readUserInput {
    param (
        [string] $message,
        [string] $regexp = ".+",
        [string] $errorMsg = "Введены некорректные данные",
        [string] $default = ""
    )
    [string] $answer = ""
    [bool] $repeat = $true
    do {
        # Проверка наличия значения по умолчанию
        if ($default -ne "") {
            $answer = $(Read-Host ("> {0} [{1}]" -f $message, $default)).Trim()
        } else {
            $answer = $(Read-Host ("> {0}" -f $message)).Trim()
        }
        # Проверка соответствия пользовательского ввода регулярному выражению
        if ($answer -match $regexp) {
            $repeat = $false
        } else {
            if ($answer -eq "" -and $default -ne "") {
                return $default
            } else {
                [log]::warning($errorMsg)
            }
        }
    } while ($repeat)
    return $answer
}

# Функция расчета хэшa sha256
function sha256 {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $plaintext 
    )
    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256')
    $hash = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($plaintext))
    $hashString = [System.BitConverter]::ToString($hash)
    $hashString.Replace('-', '').ToLower()
}

# Класс реализует механизм связи с маршрутизатором MikroTik по SSH
class mikrotik {
    hidden [System.Object] $ssh

    hidden [string] $address = "192.168.88.1"
    hidden [uint16] $port = 22
    hidden [string] $user = "admin"
    hidden [securestring] $pass = (new-object System.Security.SecureString)

    # Набор конструкторов с возможностью переопределения параметров подключения
    mikrotik() {}
    mikrotik([bool] $setup) {
        if ($setup) {
            if ($(readUserInput -message "Использовать стандартные настройки для подключения к маршрутизатору?" -regexp "^(y|n)$" -default "n") -ne "y") {
                $this.address = readUserInput -message "Адрес" -regexp "^((\d+)(\.\d+){3})|([a-z0-9_\.]{5,20})$" -default $this.address
                $this.port = (readUserInput -message "SSH порт" -regexp "^\d+$" -default $this.port) -as[uint16]
                $this.user = readUserInput -message "Пользователь" -default $this.user
                $this.pass = readUserInputSecure -message "Пароль"
            }
        }
    }

    # Подключение к маршрутизатору MikroTik по SSH
    [void] connect() {
        do {
            [bool] $repeat = $false
            try {
                do {
                    [log]::info(("Подключение к {0}" -f $this.address))
                    $this.close()
                    $this.ssh = New-SSHSession -ErrorAction Stop -Force -ConnectionTimeout 15 -ComputerName $this.address -Port $this.port -Credential $(New-Object System.Management.Automation.PSCredential(
                        $this.user,
                        $this.pass
                    )) 2> $null
                } while (-not $this.connected())
            } catch {
                [log]::warning("Ошибка подключения: {0}" -f $_.exception.Message)
                if ($(readUserInput -message "попытаться еще раз с этими настройками?" -regexp "^(y|n)$" -default "n") -eq "y") {
                    $repeat = $true
                }
            }
        } while($repeat)
    }

    # Получение статуса текущей сессии
    [bool] connected() {
        return ($this.ssh.connected -eq $true)
    }

    # Закрытие сессии
    [void] close() {
        Get-SSHSession | Remove-SShSession
    }

    # Выполнение команды на маршрутизаторе MikroTik
    [System.Object] console([string] $instructions) {
        try {
            return $(Out-String -InputObject $(Invoke-SSHCommand -Command $instructions -SessionId $this.ssh.SessionId -TimeOut 10).Output) -replace "`n+$", ''
        } catch {
            #[log]::warning($_.exception.message)
        }
        return ""
    }

    # Выполнение команды на маршрутизаторе MikroTik с передачей результата в пользовательскую функцию
    # Если функция не назначена в конструкторе меню, то будет установлена функция вывода на экран
    [string] console([string] $instructions, $callback) {
        [string] $answer = $this.console($instructions)
        if ($answer.length -ne 0 -and $callback.GetType().name -eq "ScriptBlock") {
            return $callback.Invoke($answer)
        }
        return ""
    }

    # Получение данных о подключении без возможности изменения
    # Может использоваться в пользовательских функция принимаемых в виде команды в конструкторе cmd
    [string] getAddress() { return $this.address }
    [uint16] getPort()    { return $this.port }
    [string] getUser()    { return $this.user }
}

# Объект для описания нового типа - команда
# По сути, это просто объект для хранения информации по каждому элементу меню
class cmd {
    [string] $description
    $command # Данная переменная может быть нескольких типов, ожидаемо string и ScriptBlock но может что-то еще если кто-то реализует альтернативное меню
    [ScriptBlock] $callback

    # Описание и команда
    cmd([string] $description, $command) {
        $this.description = $description
        $this.command = $command        
    }

    # Описание, команда и пользовательская функция обработки ответа маршрутизатора
    cmd([string] $description, $command, [ScriptBlock] $callback) {
        $this.description = $description
        $this.command = $command
        $this.callback = $callback
    }
}

# Класс отвечает за формирование меню
class commands {
    [array] $cmd = @()
    [mikrotik] $mikrotik

    commands() {
        $this.add("выход", "")
    }

    # Добавление нового элемента меню
    # $command - может быть двух типов
    #   [string] простой набор команд с синтаксисом скриптов MikroTik
    #   [ScriptBlock] пользовательская функция, всегда должна возвращать значение с типом [string]
    [void] add([string] $descriptin, $command) {
        $this.cmd += [cmd]::new($descriptin, $command, {
            Param([string] $answer)
            if ($answer -match "no such item") {
                [log]::warning("Маршрутизатор сообщил об отсутствии запрашиваемой информации`n")
            } else {
                [log]::message($answer)
            }
        })
    }

    # Добавление нового элемента меню с пользовательской функцией для обработки вывода
    [void] add([string] $descriptin, $command, [ScriptBlock] $callback) {
        $this.cmd += [cmd]::new($descriptin, $command, $callback)
    }

    # Построение меню для пользователя
    hidden [void] print() {
        [log]::info("Список команд:")        
        $maxLength = $([string[]]$this.cmd.Count).Length
        for ($i=0; $i -lt $this.cmd.count; $i++) {
            $rightShift = $maxLength - $([string[]]$i).Length
            [log]::info((" {2}{0}. {1}" -f $i, $this.cmd[$i].description, (' ' * $rightShift)))
        }
        [log]::warning("* - зависит от аппаратной реализации`n")
    }

    # Поиск задания по номеру, полученному от пользователя
    hidden [string] search($num) {
        $command = $this.cmd[$num].command
        # Задание может содержать как набор команд для маршрутизатора, так самостоятельную функцию для реализации дополнительной интерактивности
        # Итогом работы любого варианта должно быть значение с типом String
        switch ($command.GetType().name) {
            "ScriptBlock" {
                return $command.Invoke($this.mikrotik)
            }
            "String" {
                return $command
            }
        }
        # Пустая строка не будет отправлена маршрутизатору (можно использовать в логике пользовательских функций)
        return ""
    }

    # Обработка пользовательского ввода
    [void] execute() {
        while ($true) {
            [log]::info("Настройка и диагностика маршрутизаторов MikroTik")

            $this.mikrotik = [mikrotik]::new($true)
            $this.mikrotik.connect()

            while ($this.mikrotik.connected()) {
                $this.print()
                $case = readUserInput -message ("Введите номер команды (0-{0})" -f ($this.cmd.count - 1)) -regexp "^(\d+)$"
                # Соединение может быть потеряно пока ожидается пользовательский ввод
                if (-not $this.mikrotik.connected()) { break }
                # Пользователь выбрал "выход"
                if ($case -eq 0) { return }
                # Обработка остальных заданий
                if (($case -as[uint16]) -lt $this.cmd.count) {
                    [log]::info("* {0}" -f $this.cmd[$case].description)
                    [string] $instructions = $this.search($case)
                    # Контроль возвращаемых значений от заданий, позволяет реализовать необходимую интерактивность без запроса к маршрутизатору
                    if ($instructions -match "^{break}$") { break }
                    # Отправка команды на маршрутизатор возможна только при условии наличия самой команды в заданиях
                    if ($instructions.length -ne 0) {
                        $this.mikrotik.console($instructions, $this.cmd[$case].callback)
                    }
                } else {
                    [log]::warning("Команда не поддерживается")
                }
                # Повторно выводим меню после подтверждения пользователя, т.к. его размер может сильно сдвинуть вывод от выполненной ранее команды
                if ($(readUserInput -message "Вернуться к меню?" -regexp "^(y|n)$" -default "y") -eq "n") {
                    break
                }
            }

            [log]::warning("Соединение не установлено или потеряно`n")
            $this.mikrotik.close()
        }
    }
}

# Установка обязательных пакетов, требует наличие интернета при первом запуске скрипта
# При всех последующих запусках интернет НЕ ТРЕБУЕТСЯ!
if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
    try {
        [log]::info("Установка необходимых пакетов из сети интернет")
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | out-null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name Posh-SSH -Scope CurrentUser
    } catch {
        [log]::warning("Ошибка во время установки: {0}" -f $_.exception.Message)
        exit 1
    }
}

Import-Module Posh-SSH

# ------------------------------------------------------------------------------
# Функции используемые в обработчиках меню
# ------------------------------------------------------------------------------

# Сброс настроек маршрутизатора с предварительным подтверждением от пользователя
[ScriptBlock] $reset_f = {
    if ((readUserInput -message "Подтвердите выполнение сброса настроек" -regexp "^(y|n)$" -default "n") -eq "y") {
        [log]::info("Команда сброса отправлена")
        return "system reset-configuration; quit"
    }

    return ""
}

# Функция подсветки вывода после icmp проверки
# Цвет меняется в зависимости от количества потерянных пакетов
[ScriptBlock] $ping_f = {
    Param($answer)

    [ConsoleColor] $color = 'White'
    if ($answer -match 'packet-loss=(?<loss>\d+)%') {
        if ($Matches.loss -eq 0) { $color = 'Green' }
        elseif ($Matches.loss -le 10) { $color = 'Yellow' }
        else { $color = 'Red' }
    }

    Write-Host $answer -ForegroundColor $color
}

# Функция организует пользовательский ввод
# Запрашивает имя узла для последующего формирования команды ping
# Проверка пользовательского ввода обязательна т.к иначе можно попасть в беду
[ScriptBlock] $getIpAddress_f = {
    $address = readUserInput -message "Введите адрес хоста" -regexp "^((\d+)(\.\d+){3})|([a-z0-9_\.]{5,20})$"
    return 'ping count=5 address={0}' -f $address
}

# Функция мониторинга состояния LTE
# Реализован механизм периодического опроса маршрутизатора и обновление данных в консоли
# Решает задачу юстировки антенны по полученным данным
[scriptblock] $lte_antenna_alignment_f = {
    Param([mikrotik] $mikrotik)
   
    [Console]::TreatControlCAsInput = $True
    Start-Sleep -Seconds 1
    $Host.UI.RawUI.FlushInputBuffer()

    while ($mikrotik.connected()) {
        # Ctrl+C: 3
        # ESC: 27
        if ($Host.UI.RawUI.KeyAvailable -and ($Key = $Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
            if (([Int]$Key.Character -eq 3) -or ([Int]$Key.Character -eq 27)) {
                break
            }
        }

        $answer = $mikrotik.console('interface lte monitor 0 once') -replace "(\s+)?(imei|imsi|uicc):\s.+",""
        
        [System.Console]::Clear()
        [log]::message("")
        foreach($str in $answer -split "`n") {
            if ($str -match "^(?<prefix>\s+)?(?<param>(rssi|rsrp|rsrq|sinr)):\s+(?<value>\-?\d+)(?<postfix>[a-z]+)") {
                $backgroundColor = "Red"
                $foregroundColor = "Black"
                [log]::message(("{0}{1}: " -f $Matches.prefix, $Matches.param), $false)
                switch ($Matches.param) {
                    rssi {
                        if ([int]$Matches.value     -gt -65)  { $backgroundColor = "Green" }
                        elseif ([int]$Matches.value -gt -75)  { $backgroundColor = "Yellow" }
                        elseif ([int]$Matches.value -gt -85)  { $backgroundColor = "Magenta" }
                    }
                    rsrp {
                        if ([int]$Matches.value     -gt -84)  { $backgroundColor = "Green"}
                        elseif ([int]$Matches.value -gt -102) { $backgroundColor = "Yellow" }
                        elseif ([int]$Matches.value -gt -111) { $backgroundColor = "Magenta" }
                    }
                    rsrq {
                        if ([int]$Matches.value     -gt -5)   { $backgroundColor = "Green" }
                        elseif ([int]$Matches.value -gt -9)   { $backgroundColor = "Yellow" }
                        elseif ([int]$Matches.value -gt -12)  { $backgroundColor = "Magenta" }
                    }
                    sinr {
                        if ([int]$Matches.value     -gt 12.5) { $backgroundColor = "Green" }
                        elseif ([int]$Matches.value -gt 10)   { $backgroundColor = "Yellow" }
                        elseif ([int]$Matches.value -gt 7)    { $backgroundColor = "Magenta" }
                    }
                }
                Write-Host (" {0}{1} " -f $Matches.value, $Matches.postfix) -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor
            } else {
                [log]::message($str)
            }
        }
        [log]::info('Нажмите "ESC" или "CTRL+C", чтобы остановить мониторинг')

        Start-Sleep -s 1
    }

    [Console]::TreatControlCAsInput = $False
    $Host.UI.RawUI.FlushInputBuffer()

    return ""
}

# Функция реализующая поиск хоста по ARP таблицы
# В ARP таблице RouterOS также отображается имя интерфейса
[scriptblock] $arp_host_search_f = {
    Param($mikrotik)

    [string] $identity = readUserInput -message "Введите адрес хоста"

    $answer = $mikrotik.console('ip arp print')

    [log]::message('')
    foreach($str in $answer -split "`n") { 
        if ($str -match ("\s{0}\s" -f [regex]::escape($identity))) {
            [log]::info($str)
        } else {
            [log]::message($str)
        }
    }

    return ""
}

[scriptblock] $routerboard_info_f = {
    Param($answer)

    $list = [ordered]@{}
    $maxParamLength = 0
    foreach($obj in ([regex]"(\s+)?(?<param>[^:]+):\s+(?<value>.+)\n").Matches($answer)) {
        if ($obj.Groups["param"].length -gt $maxParamLength) {
            $maxParamLength = $obj.Groups["param"].length
        }
        $list.Add($obj.Groups["param"], $obj.Groups["value"])
    }

    [log]::message('')
    foreach($obj in $list.GetEnumerator()) {
        [log]::message(("{2}{0}: {1}" -f $obj.key, $obj.value, (" " * ($maxParamLength - $obj.key.Length))))
    }
    [log]::message('')
}

# ------------------------------------------------------------------------------
# Наполнение меню
# ------------------------------------------------------------------------------

$commands = [commands]::new()
$commands.add("[!] cброс до заводских настроек", $reset_f)
$commands.add("информация о маршрутизаторе", "system identity print; system routerboard print; system resource print", $routerboard_info_f)
$commands.add("информация о LTE *", 'interface lte print; ip address print where interface=[/interface lte get [find]]->"name"; do command={interface lte info [find] once} on-error={interface lte monitor [find] once}')
$commands.add("информация об интерфейсах", "interface print")
$commands.add("информация об IP-адресах", "ip address print")
$commands.add("юстировка LTE антенны *", $lte_antenna_alignment_f)
$commands.add("за каким интерфейсом находится хост?", $arp_host_search_f)
$commands.add("ping Google DNS", "ping count=5 address=8.8.8.8", $ping_f)
$commands.add("ping <любой адрес>", $getIpAddress_f, $ping_f)
$commands.add("принудительно включите PoE на 5-м порту *", "interface ethernet poe set ether5 poe-out=forced-on")
$commands.add("переключить модем на первый (UP) слот SIM карты *",   "do command={system routerboard sim set sim-slot=up;}   on-error={system routerboard modem set sim-slot=up}")
$commands.add("переключить модем на второй (DOWN) слот SIM карты *", "do command={system routerboard sim set sim-slot=down;} on-error={system routerboard modem set sim-slot=down}")
$commands.execute()
