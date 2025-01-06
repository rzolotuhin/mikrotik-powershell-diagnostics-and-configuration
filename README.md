## Техническое задание
Разработать решение, которое упрощает работу монтажным бригадам по обслуживанию сетевого оборудования MikroTik.<br>
Основные требования:<br>
- С оборудованием работают монтажные бригады отвечающие, в основном, только за аппаратную работоспособность оборудования
- Минимальные знания RouterOS для эксплуатации
- Минимальный набор действий для простой диагностики или перенастройки оборудования
- Возможность расширять функционал силами специалистов по системному администрированию
- Работа под операционной системой Windows

## Решение
PowerShell скрипт в качестве простой прослойки между сетевым оборудованием и человеком.<br>
- Встроенное решение Microsoft
- Не высокий порог входа
- Не требует компиляции
- Может быть легко модифицирован

## Описание
Скрипт использует SSH для подключения к оборудованию.<br>
При запуске, он проверит зависимости на наличие модуля `Posh-SSH`, и установит его в случае необходимости.

Скрипт формирует меню в виде нумерованного списка, где каждый пункт описывает какое-то определенное действие, которое необходимо выполнить на стороне оборудования.
От получения информации о состоянии оборудования, до его перенастройки под какие-то задачи.

Для выполнения действия необходимо ввести номер пункта меню.

## Формирование меню
Объявляем экземпляр класса `commands`.
```powershell
$commands = [commands]::new()
```
Добавляем новый пункт меню
```powershell
$commands.add("ping Google DNS", "ping count=5 address=8.8.8.8")
```
Запускаем обработчик
```powershell
$commands.execute()
```
В меню будет отображаться новый пункт `ping Google DNS` за которым скрывается команда, которая будут выполнена на стороне MikroTik - `ping count=5 address=8.8.8.8`.<br>
Результат ее работы будет отображен в интерфейсе.

<span style="background-color:rgb(255, 205, 56); color: black; padding: 0.1em 0.5em 0.1em 0.5em">
ВНИМАНИЕ: не используйте команды, которые блокируют вывод и ожидают специальной комбинации клавиш для прерывания!
</span>

[Как реализовать этот механизм, описано ниже](#как-реализовать-постоянный-опрос-состояния-чего-то).

## Пример того, как может выглядеть наполненное меню
```powershell
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
```

![](/doc/images/menu_0.png)

![](/doc/images/menu_1.png)

## Различные варианты работы с методом `.add`
В качестве первого параметра всегда указывается описание, которое будет отображаться в меню.

### `.add([string]<description>, [string]<MikroTik cli command>)`
Простой пример, которым мы рассмотрели выше.<br>
В качестве второго параметра указывается валидная консольная команда RouterOS
```powershell
$commands.add("<description>", "<MikroTik cli command>")
```

### `.add([string]<description>, [scriptblock]<user function>)`
В качестве второго параметра можно указать пользовательскую функцию.<br>
Это отличный вариант, если необходимо добавить интерактивность, например, запросить подтверждение выполняемого действия.
```powershell
[ScriptBlock] $reset_f = {
    if ((readUserInput -message "Подтвердите выполнение сброса настроек" -regexp "^(y|n)$" -default "n") -eq "y") {
        [log]::info("Команда сброса отправлена")
        return "system reset-configuration; quit"
    }

    return ""
}
```
```powershell
$commands.add("[!] cброс до заводских настроек", $reset_f)
```
Пользовательская функция должна вернуть один из трех вариантов строки:
- `<консольная команда RouterOS>` - эта команда будет отправлена маршрутизатору. Интерактивность позволяет вносить изменения в команду в процессе выполнения.
- `{break}` - специальная внутренняя команда, которая приведет к закрытию `ssh` сессии и отключению от оборудования.
- `пустая строка` - расценивается как отсутствие команды, что приведет к выходу в основное меню скрипта. Подключение не будет разорвано.

Если понадобится что-то отобразить пользователю, используйте стандартные методы `PowerShell` или методы класса `log`.<br>
Во всех остальных случаях, стоит подавить вывод через `out-null`, иначе эти данные будут восприниматься скриптом как команды, которые необходимо выполнить в RouterOS.<br>
Хорошей практикой, для передачи команд, будет использование только `return`

![](/doc/images/user_function_0.png)

Также пользовательской функции будет передан один аргумент `Param($mikrotik)`, это экземпляр класса `mikrotik` с открытой `ssh` сессией с сетевым оборудованием.<br>
Это позволит отправлять консольные команды и самостоятельно обрабатывать их результат, выстраивая необходимое поведение.<br>
```powershell
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
```
```powershell
$commands.add("за каким интерфейсом находится хост?", $arp_host_search_f)
```
![](/doc/images/arp_host_search_f_0.png)

### `.add([string]<description>, [string]<MikroTik cli command>, [scriptblock]<user function>)`
В качестве третьего параметра также можно указать пользовательскую функцию, которой будет передан ответ RouterOS на консольную команду.<br>
Это позволяет производить различные манипуляции с полученными данными.<br>
Например, можно: отфильтровать вывод, отформатировать его, сохранить в файл, или сделать все, что Вам потребуется.

Пользовательской функции будет передан один аргумент `Param($answer)`, который будет содержать ответ на консольную команду RouterOS.

```powershell
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
```
```powershell
$commands.add("ping Google DNS", 'ping count=5 address=8.8.8.8', $ping_f)
```
В данном примере, цвет вывода будет меняться в зависимости от количества потерянных icmp пакетов.

### `.add([string]<description>, [scriptblock]<user function>, [scriptblock]<user function>)`
- `второй параметр` - функция `getIpAddress_f`, которая запрашивает у пользователя адрес хоста
- `третий параметр` - функция `ping_f`, которая форматирует ответ от RouteOS

```powershell
[ScriptBlock] $getIpAddress_f = {
    $address = readUserInput -message "Введите адрес хоста" -regexp "^((\d+)(\.\d+){3})|([a-z0-9_\.]{5,20})$"
    return 'ping count=5 address={0}' -f $address
}

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
```
```powershell
$commands.add("ping <любой адрес>", $getIpAddress_f, $ping_f)
```

![](/doc/images/ping_0.png)
![](/doc/images/ping_1.png)

## Совместимость команд RouterOS v6 и v7
Хоть в RouterOS v7 есть обратная совместимость с консольными командами v6, сам MikroTik ничего не гарантирует.<br>
Например, необходимо получить состояние LTE модема.

RouterOS v6
```powershell
$commands.add("информация о LTE", "interface lte info 0 once")
```

RouterOS v7
```powershell
$commands.add("информация о LTE", "interface lte monitor 0 once")
```

RouterOS v6 & v7
```powershell
$commands.add("информация о LTE", "do command={interface lte info 0 once} on-error={interface lte monitor 0 once}")
```

## Как реализовать постоянный опрос состояния <чего-то>
На примере конкретной задачи по юстировке LTE антенны, требуется постоянно мониторить состояние модема и метрики `rssi`, `rsrp`, `rsrq` и `sinr`.<br>
В RouterOS, в зависимости от версии, мы бы воспользовались командой `interface lte info 0` или `interface lte monitor 0`, при условии, что у нас всего оди LTE модем.<br>
Но, данная команда без параметра `once` заблокирует вывод и будет постоянно отправлять данные, скрипт не получит признак конца сообщения, и не отобразит ничего.

Решением является самостоятельный регулярный опрос модема.<br>
Немного усложним задачу, и добавим цветовую градацию для лучшего понимания получаемых значений метрик.
```powershell
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

        $answer = $mikrotik.console('interface lte monitor 0 once')
        
        [System.Console]::Clear()
        [log]::message("")
        foreach($str in ($answer -replace "(\s+)?(imei|imsi|uicc):\s.+","") -split "`n") {
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
```
```powershell
$commands.add("юстировка LTE антенны *", $lte_antenna_alignment_f)
```

Обратите внимание, что запрос данных и их обработку мы проводим в одной пользовательской функции.

![](/doc/images/lte_antenna_alignment_f_0.png)
![](/doc/images/lte_antenna_alignment_f_1.png)

## Авторизация и безопасность
При запуске скрипт спросит: 
> Использовать стандартные настройки для подключения к маршрутизатору?

Под стандартными настройками подразумеваются данные, используемые с завода для подключения к оборудованию под управлением RouterOS v6.<br>
- 192.168.88.1:22
- admin
- без пароля

Начиная с RouterOS v7, учетная запись `admin` имеет установленный с завода пароль, который написан на наклейке где-то на железе. Соответственно, у каждой железки, из коробки, он уникальный и подключиться "стандартным способом", без пароля, не получится.<br>
Возможно, для плат RouterBoard поставляемых с RouterOS v7, дефолтный скрипт конфигурации, расположенный в системе, не устанавливает пароль для сброшенного оборудования. Это нужно проверять.

Все необходимые параметры описаны в свойствах класса `mikrotik`. Пароль не задан.
```powershell
class mikrotik {
    hidden [string] $address = "192.168.88.1"
    hidden [uint16] $port = 22
    hidden [string] $user = "admin"
    hidden [securestring] $pass = (new-object System.Security.SecureString)
}
```
Эти значения также будут предложены для подстановки в случае ручного заполнения. Это упрощает процесс, если разное оборудование отличается только паролем.

![](/doc/images/connect_0.png)

Может возникнуть соблазн сохранить пароль в скрипте, это будет огромной ошибкой.<br>
Даже если пароль будет не в виде `PlainText`, а в виде зашифрованной строки, полученной через `ConvertFrom-SecureString`, данные можно легко расшифровать.<br>
Даже если использовать 192 битный ключ шифрования, он понадобится для обратной операции, что приведет к вопросу хранения самого ключа...

Подробнее можно почитать тут
- [ConvertTo-SecureString](https://learn.microsoft.com/ru-ru/powershell/module/microsoft.powershell.security/convertto-securestring?view=powershell-7.4)
- [ConvertFrom-SecureString](https://learn.microsoft.com/ru-ru/powershell/module/microsoft.powershell.security/convertfrom-securestring?view=powershell-7.4)

<span style="background-color:rgb(255, 205, 56); color: black; padding: 0.1em 0.5em 0.1em 0.5em">
Не сохраняйте пароль в скрипте!
</span>


## PS
Я не стал приводить примеры того, как можно полностью настраивать оборудование под какие-то задачи, т.к. они у всех свои. Но имеющихся примеров должно быть достаточно для понимания процесса.<br>
В боевых условиях, данное решение справлялось с начальной диагностикой, полной автоматической настройкой оборудования, настройкой различных VPN и т.д.<br>

И еще раз отмечу, это просто вариант решения интересной технической задачи.