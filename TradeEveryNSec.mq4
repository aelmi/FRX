#property copyright "Al Elmi"
#property link      "http://www.yourwebsite.com"
#property version   "1.14"
#property strict

// Input parameters
extern string TradeSymbolsAndLots = "US30=0.5,NDAQ100=1,GOLD=1,USOIL=0.4";
extern int MaxTradesTotal = 30;     // Maximum number of open trades across all symbols
extern int MaxTradesPerSymbol = 8;  // Maximum number of open trades per symbol
extern double TakeProfit = 3.0;     // Take profit in dollars
extern int TradeInterval = 4;       // Time between trades in seconds
extern int ShortMAPeriod = 10;      // Period for the Short Simple Moving Average
extern int LongMAPeriod = 20;       // Period for the Long Simple Moving Average
extern double MinProfitToCloseTrades = 1000.0; // Minimum profit to close trades when account value is negative

datetime lastTradeTime = 0;
string symbolArray[];
double lotSizes[];
int symbolCount = 0;

int OnInit()
{
    string pairs[];
    symbolCount = StringSplit(TradeSymbolsAndLots, ',', pairs);
    
    if(symbolCount == 0)
    {
        Print("Error: No valid symbols provided");
        return INIT_FAILED;
    }
    
    ArrayResize(symbolArray, symbolCount);
    ArrayResize(lotSizes, symbolCount);
    
    for(int i = 0; i < symbolCount; i++)
    {
        string symbolLot[];
        if(StringSplit(pairs[i], '=', symbolLot) == 2)
        {
            symbolArray[i] = symbolLot[0];
            lotSizes[i] = StringToDouble(symbolLot[1]);
        }
        else
        {
            Print("Error: Invalid symbol-lot pair: ", pairs[i]);
            return INIT_FAILED;
        }
    }
    
    Print("Trading on ", symbolCount, " symbols: ", TradeSymbolsAndLots);
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    // Check and close profitable trades for all symbols
    for(int i = 0; i < symbolCount; i++)
    {
        CheckAndCloseProfitableTrades(symbolArray[i]);
    }
    
    // Check if TradeInterval seconds have passed since the last trade
    if(TimeCurrent() - lastTradeTime >= TradeInterval)
    {
        int totalOpenTrades = CountTotalOpenTrades();
        
        // Trade on each symbol
        for(int i = 0; i < symbolCount; i++)
        {
            string currentSymbol = symbolArray[i];
            
            // Check if the number of open trades for this symbol is less than MaxTradesPerSymbol
            // and if the total number of open trades is less than MaxTradesTotal
            if(CountOpenTrades(currentSymbol) < MaxTradesPerSymbol && totalOpenTrades < MaxTradesTotal)
            {
                int tradeDirection = DetermineTradeDirection(currentSymbol);
                
                // Check if there are no open trades in the opposite direction for this symbol
                if(CountOpenTradesInOppositeDirection(currentSymbol, tradeDirection) == 0)
                {
                    // Open trades in the determined direction with appropriate lot size
                    if(tradeDirection != -1 && IsTradingSession(currentSymbol))
                    {
                        double lotSize = GetDynamicLotSize(currentSymbol);
                        if(OpenTrade(currentSymbol, lotSize, tradeDirection))
                        {
                            totalOpenTrades++;
                        }
                    }
                }
            }
        }
        
        lastTradeTime = TimeCurrent();
    }
}

double GetDynamicLotSize(string symbol)
{
    double accountEquity = AccountEquity();
    double riskPercentage = 0.01; // 1% of equity per trade
    double stopLossInPips = 50; // Hypothetical stop loss level
    double lotSize = (accountEquity * riskPercentage) / (stopLossInPips * MarketInfo(symbol, MODE_TICKVALUE));
    return NormalizeDouble(lotSize, 2);
}

int DetermineTradeDirection(string symbol)
{
    double shortMA = iMA(symbol, 0, ShortMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
    double longMA = iMA(symbol, 0, LongMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
    double rsi = iRSI(symbol, 0, 14, PRICE_CLOSE, 0); // 14-period RSI

    if(shortMA > longMA && rsi < 70)
        return OP_BUY;
    else if(shortMA < longMA && rsi > 30)
        return OP_SELL;
    else
        return -1; // No clear direction
}

bool OpenTrade(string symbol, double lots, int tradeType)
{
    double price = (tradeType == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
    int ticket = OrderSend(symbol, tradeType, lots, price, 3, 0, 0, "Trade", 0, 0, (tradeType == OP_BUY) ? clrGreen : clrRed);
    
    if(ticket > 0)
    {
        Print("Trade opened successfully on ", symbol, ". Ticket: ", ticket);
        return true;
    }
    else
    {
        Print("Error opening trade on ", symbol, ". Error code: ", GetLastError());
        return false;
    }
}

void CheckAndCloseProfitableTrades(string symbol)
{
    double accountEquity = AccountEquity();
    
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == symbol)
            {
                double profit = OrderProfit();
                double trailProfit = OrderOpenPrice() + TakeProfit * Point * OrderType();
                double newPrice = (OrderType() == OP_BUY) ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);

                if(newPrice > trailProfit)
                {
                    trailProfit = newPrice - (TakeProfit * Point);
                }
                
                if(profit >= TakeProfit && (accountEquity >= 0.0 || profit >= MinProfitToCloseTrades))
                {
                    if(!OrderClose(OrderTicket(), OrderLots(), newPrice, 3, clrYellow))
                    {
                        Print("Error closing trade on ", symbol, ". Error code: ", GetLastError());
                    }
                    else
                    {
                        Print("Trade closed with profit on ", symbol, ": ", profit);
                    }
                }
            }
        }
    }
}

int CountOpenTrades(string symbol)
{
    int count = 0;
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == symbol)
            {
                count++;
            }
        }
    }
    return count;
}

int CountTotalOpenTrades()
{
    int count = 0;
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            count++;
        }
    }
    return count;
}

int CountOpenTradesInOppositeDirection(string symbol, int tradeDirection)
{
    int count = 0;
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == symbol && OrderType() != tradeDirection)
            {
                count++;
            }
        }
    }
    return count;
}

bool IsTradingSession(string symbol)
{
    // Example: Only trade during London and New York sessions
    datetime currentTime = TimeCurrent();
    int hour = TimeHour(currentTime);

    if((hour >= 8 && hour <= 17) || (hour >= 13 && hour <= 21))
        return true;

    return false;
}
