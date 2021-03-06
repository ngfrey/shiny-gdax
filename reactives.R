#### Monitor tab ####
# Load products
products <- getProducts(proxy = proxy)

# Update base currency selections (BTC default)
updateSelectInput(session, "baseCurrency",
                  choices = unique(products$base_currency),
                  selected = "BTC")

# Update quote currency selections (USD default)
quotes <- products$quote_currency[which(products$base_currency == "BTC")]
updateSelectInput(session, "quoteCurrency", choices = quotes, selected = "USD")

# Define separate reactive values for base and quote currency selections
values <- reactiveValues(product = "BTC-USD")

# Update reactive values
observe({
  req(input$quoteCurrency)
  values$product <- paste(isolate(input$baseCurrency), "-", input$quoteCurrency, sep = "")
})

# Update quote currency selections whenever new base is selected
# Keep quote currency persistent when changing base currency (whenever possible)
observe({
  req(input$baseCurrency)
  quotes <- sort(products$quote_currency[which(products$base_currency == input$baseCurrency)])
  if (isolate(input$quoteCurrency) %in% quotes) {
    updateSelectInput(session, "quoteCurrency", choices = quotes, selected = isolate(input$quoteCurrency))
    values$product <- paste(isolate(input$baseCurrency), "-", input$quoteCurrency, sep = "")
  } else if ("USD" %in% quotes) {
    updateSelectInput(session, "quoteCurrency", choices = quotes, selected = "USD")
  } else {
    updateSelectInput(session, "quoteCurrency", choices = quotes, selected = quotes[1])
  }
})

# Update product historic prices automatically based on granularity
makeReactiveBinding("price")
observe({
  invalidateLater(as.numeric(input$granularity)*1000)
  price <<- getProductHistoricRates(values$product, granularity = input$granularity, proxy = proxy)
})

# Update product order book automatically every second
makeReactiveBinding("book")
observe({
  invalidateLater(1000)
  book <<- getProductOrderBook(values$product, level = 2, proxy = proxy)
})

# Price graph
output$priceGraph <- renderDygraph({
  data <- price
  if (input$graphType == "line") {
    dygraph(xts(data$open, order.by = data$time)) %>%
      dySeries("V1", label = "Price") %>%
      dyRangeSelector(retainDateWindow = T) %>%
      dyLegend(labelsDiv = "priceLegend", show = "always")
  } else {
    dygraph(xts(data.frame(O = data$open,
                           H = data$high,
                           L = data$low,
                           C = data$close),
                order.by = data$time)) %>%
      dyRangeSelector(retainDateWindow = T) %>%
      dyCandlestick() %>%
      dyLegend(labelsDiv = "priceLegend")
  }
})

# Order depth graph
# JS formatter for prettier x (price) legend in depth graph
priceFormat <- 'function (x) {return "price: ".bold().concat(x.toString());}'

# Render graph
output$orderDepthGraph <- renderDygraph({
  data <- data.frame(xlab = c(rev(book$bids$price), book$asks$price),
                     bids = c(rev(cumsum(book$bids$size)), rep(NA, nrow(book$asks))),
                     asks = c(rep(NA, nrow(book$bids)), cumsum(book$asks$size)))

  dygraph(data) %>%
    dySeries("bids", fillGraph = T, stepPlot = T, color = "green") %>%
    dySeries("asks", fillGraph = T, stepPlot = T, color = "red") %>%
    dyAxis(name = "x", valueFormatter = priceFormat) %>%
    dyOptions(retainDateWindow = T)
})

#### About tab ####
# Render currency table
output$currencyTable <- renderDataTable({
  table <- getCurrencies(proxy = proxy)
  table <- table[order(table$details$sort_order),]
  table <- cbind(table[,c("id","name","min_size")], table$details[,c("type","symbol")])
  colnames(table) <- c("id", "name", "min size", "type", "symbol")
  table
}, options = list(
  paging = F,
  searching = F,
  ordering = F,
  info = F,
  fixedColumns = T
))

# Render product table
output$productTable <- renderDataTable({
  table <- products
  table <- table[,c("id", "base_currency", "quote_currency", "margin_enabled")]
  colnames(table) <- c("id", "base", "quote", "margin")
  table
}, options = list(
  paging = F,
  searching = F,
  ordering = F,
  info = F,
  fixedColumns = T
))
