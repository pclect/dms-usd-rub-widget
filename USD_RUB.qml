
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property real rate: 0
    property real previousRate: 0
    property string rateDate: ""
    property bool requestFailed: false
    property int rateRetryAttempt: 0

    property var historyRates: []
    property bool historyLoading: false
    property bool historyFailed: false

    readonly property string rateText:
        rate > 0
        ? rate.toFixed(2).replace(".", ",")
        : "—"

    readonly property string trend:
        rate > previousRate ? " ↑"
        : rate < previousRate ? " ↓"
        : ""

    function scheduleRateRetry() {
        requestFailed = true

        if (rateRetryTimer.running)
            return

        const delays = [10000, 20000, 40000, 60000]
        const index = Math.min(rateRetryAttempt, delays.length - 1)

        rateRetryTimer.interval = delays[index]
        rateRetryAttempt = Math.min(
            rateRetryAttempt + 1,
            delays.length - 1
        )

        rateRetryTimer.start()
    }

    function refreshRate() {
        const xhr = new XMLHttpRequest()

        xhr.open(
            "GET",
            "https://www.cbr-xml-daily.ru/daily_json.js"
        )

        xhr.timeout = 15000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return

            if (xhr.status !== 200) {
		root.scheduleRateRetry()                
		return
            }

            try {
                const data = JSON.parse(xhr.responseText)
                const usd = data.Valute.USD

                if (!usd || !usd.Value || !usd.Nominal)
                    throw new Error("Invalid USD data")

                root.rate =
                    Number(usd.Value) / Number(usd.Nominal)

                root.previousRate =
                    Number(usd.Previous) / Number(usd.Nominal)

		root.rateDate = data.Date
		root.requestFailed = false
		root.rateRetryAttempt = 0
		root.rateRetryTimer.stop()               

            } catch (error) {
                console.log("USD/RUB: " + error)
		root.scheduleRateRetry()       
            }
        }

        xhr.onerror = function() {
	    root.scheduleRateRetry()
        }

        xhr.ontimeout = function() {
	    root.scheduleRateRetry()
        }

        xhr.send()
    }

    // Загрузка истории через предыдущие публикации ЦБ РФ
    function loadHistory() {
        if (historyLoading)
            return

        historyRates = []
        historyLoading = true
        historyFailed = false

        fetchHistory(
            "https://www.cbr-xml-daily.ru/daily_json.js",
            21
        )
    }

    function fetchHistory(url, remaining) {
        const xhr = new XMLHttpRequest()

        xhr.open("GET", url)
        xhr.timeout = 15000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return

            if (xhr.status !== 200) {
                root.historyFailed = true
                root.historyLoading = false
                return
            }

            try {
                const data = JSON.parse(xhr.responseText)
                const usd = data.Valute.USD

                if (!usd || !usd.Value || !usd.Nominal)
                    throw new Error("Invalid history data")

                const item = {
                    date: data.Date,
                    rate: Number(usd.Value) /
                          Number(usd.Nominal)
                }

                root.historyRates =
                    root.historyRates.concat([item])

                if (remaining > 0 && data.PreviousURL) {
                    let nextUrl = data.PreviousURL

                    if (nextUrl.startsWith("//"))
                        nextUrl = "https:" + nextUrl

                    root.fetchHistory(nextUrl, remaining - 1)
                } else {
                    root.historyRates =
                        root.historyRates.slice().reverse()

                    root.historyLoading = false
                }

            } catch (error) {
                console.log("USD/RUB history: " + error)
                root.historyFailed = true
                root.historyLoading = false
            }
        }

        xhr.onerror = function() {
            root.historyFailed = true
            root.historyLoading = false
        }

        xhr.ontimeout = function() {
            root.historyFailed = true
            root.historyLoading = false
        }

        xhr.send()
    }

    function historyMin() {
        if (historyRates.length === 0)
            return 0

        let result = historyRates[0].rate

        for (let i = 1; i < historyRates.length; i++)
            result = Math.min(result, historyRates[i].rate)

        return result
    }

    function historyMax() {
        if (historyRates.length === 0)
            return 0

        let result = historyRates[0].rate

        for (let i = 1; i < historyRates.length; i++)
            result = Math.max(result, historyRates[i].rate)

        return result
    }

    function historyChange() {
        if (historyRates.length < 2)
            return 0

        const first = historyRates[0].rate
        const last = historyRates[historyRates.length - 1].rate

        return ((last - first) / first) * 100
    }

    Component.onCompleted: startupTimer.start()

    Timer {
        id: startupTimer
        interval: 7000
        repeat: false
        onTriggered: root.refreshRate()
    }

    Timer {
        id: rateRetryTimer
        interval: 10000
        running: false
        repeat: false
        onTriggered: root.refreshRate()
    }

    Timer {
        interval: 3600000
        running: true
        repeat: true
        onTriggered: root.refreshRate()
    }

    // Компактный индикатор на панели

horizontalBarPill: Component {
    StyledRect {
        id: pill

        // Естественный размер плашки для расчёта компоновки DMS
        implicitWidth: label.implicitWidth + Theme.spacingXS * 2
        implicitHeight: parent.widgetThickness

        // Фактический размер
        width: implicitWidth
        height: implicitHeight

        radius: Theme.cornerRadius
        color: Theme.chipSurface

        StyledText {
            id: label

            anchors.centerIn: parent

            text: "＄ " + root.rateText + root.trend

            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
    verticalBarPill: horizontalBarPill

    // Всплывающее окно
    popoutWidth: 390
    popoutHeight: 340

    popoutContent: Component {
        PopoutComponent {
            headerText: "USD / RUB"
            detailsText: "История официального курса ЦБ РФ"

            Component.onCompleted: root.loadHistory()

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: root.rate > 0
                        ? root.rateText + " ₽"
                        : "Курс недоступен"

                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeXLarge
                }

                StyledText {
                    text: root.historyRates.length > 1
                        ? (root.historyChange() >= 0 ? "▲ +" : "▼ ")
                          + Math.abs(root.historyChange()).toFixed(2)
                          + "% за период"
                        : "Изменение за месяц"

                    color: root.historyChange() >= 0
                        ? "#16A36A"
                        : "#D65A5A"

                    font.pixelSize: Theme.fontSizeSmall
                }

                // График курса
                Canvas {
                    id: chart

                    width: parent.width
                    height: 155

                    onPaint: {
                        const ctx = getContext("2d")
                        const points = root.historyRates

                        ctx.clearRect(0, 0, width, height)

                        if (points.length < 2)
                            return

                        let min = root.historyMin()
                        let max = root.historyMax()

                        if (max === min) {
                            max += 0.1
                            min -= 0.1
                        }

                        const pad = 8
                        const chartWidth = width - pad * 2
                        const chartHeight = height - pad * 2

                        ctx.beginPath()
                        ctx.lineWidth = 2
                        ctx.strokeStyle = Theme.primary

                        for (let i = 0; i < points.length; i++) {
                            const x = pad +
                                (i / (points.length - 1)) * chartWidth

                            const y = height - pad -
                                ((points[i].rate - min) /
                                (max - min)) * chartHeight

                            if (i === 0)
                                ctx.moveTo(x, y)
                            else
                                ctx.lineTo(x, y)
                        }

                        ctx.stroke()
                    }

                    Connections {
                        target: root

                        function onHistoryRatesChanged() {
                            chart.requestPaint()
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 0

                    StyledText {
                        width: parent.width / 2
                        text: root.historyRates.length > 0
                            ? root.historyRates[0].date.slice(0, 10)
                            : ""

                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        width: parent.width / 2
                        text: root.historyRates.length > 0
                            ? root.historyRates[
                                root.historyRates.length - 1
                              ].date.slice(0, 10)
                            : ""

                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Статистика
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    Column {
                        width: (parent.width - Theme.spacingS * 2) / 3

                        StyledText {
                            text: "Минимум"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            text: root.historyRates.length
                                ? root.historyMin().toFixed(2) + " ₽"
                                : "—"

                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }

                    Column {
                        width: (parent.width - Theme.spacingS * 2) / 3

                        StyledText {
                            text: "Максимум"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            text: root.historyRates.length
                                ? root.historyMax().toFixed(2) + " ₽"
                                : "—"

                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }

                    Column {
                        width: (parent.width - Theme.spacingS * 2) / 3

                        StyledText {
                            text: "Изменение"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            text: root.historyRates.length > 1
                                ? (root.historyChange() > 0 ? "+" : "")
                                  + root.historyChange().toFixed(2) + "%"
                                : "—"

                            color: root.historyChange() >= 0
                                ? "#16A36A"
                                : "#D65A5A"

                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }
                }

                StyledText {
                    visible: root.historyLoading
                    text: "Загружаю историю курса..."
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    visible: root.historyFailed
                    text: "Не удалось загрузить историю. Закрой и открой окно повторно."
                    color: "#D65A5A"
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
