; ------------------------------------------------------------------------------------------ 
;
; a simplified stock market simulation
;
; 
; Author:
; Jihe.Gao@jiejiaotech.com
; 
; ------------------------------------------------------------------------------------------
; NetLogo requires that the extensions directive resides on the first line of code
extensions [matrix stats]

breed [Stocks stock]
breed [Investors investor]

__includes ["communication.nls" "bidding.nls" "stockexchange.nls" "gp.nls"]

globals [ 
  global-wealth 
  initial-wealth-distribution 
  total-dealed-volume 
  stock-label-list 
  stock-xcor-list
  ]


turtles-own [
  incoming-queue            ; for communication
  ]


Investors-own [
  money_initial             ; 
  money
  networth
  portfolio
  portfolio-adj
  strategy
  expectations
  t-back-test               ; the time period to run back test
  t-real-test               ; the tiem period to run real-time test
]

to setup
  clear-all
  ask patches [set pcolor black]
  
  set stock-label-list ["ETF" "oil-stock" "non-oil-stock" "stock4" "stock5" "stock6" "stock7" "stock8" ]
  set stock-xcor-list [ -8 -6 -4 -2 0 2 4 6 8 10 12]

  setup-stocks num-stocks
  
  set-default-shape turtles "Person"
  setup-investors Investor-population
  
  set global-wealth sum [money] of investors
  ;; temporally remove chooser ""initial-wealth-distribution", to run online demo which cannot read string input
  set initial-wealth-distribution "normal"
  ;;
  ask investors [ 
    allocate-money 
    set networth []
    set t-real-test 10
    let random-10-list (list random 10 random 10 random 10 random 10 random 10 random 10 random 10 random 10)
    set portfolio sublist random-10-list 0 (count stocks) 
    set portfolio-adj map [? * 0] portfolio
    ;update-networth    
    ]


  reset-ticks
end

to generate-stock-historical-prices
  let tick-count 110
  while [tick-count > 0] [
    market-go "generate-price-random"
    set tick-count tick-count - 1
  ]
end


; run-options:
;    - generate-price steps - generate historical prices with previous investing strategy
;    - gp-learn             - learning new investing strategy using historical stock prices
;    - backtest             - back test current strategy's performance using historical stock prices
;    - realtest             - 
; 
to market-go [run-option]
  
  ;if tick-count > 0 and ticks > tick-count [stop]  ; set run-number = 0 for no step limit

  ; investors procedures
  update-expectations run-option
  calculate-portfolio-adj
  make-bidding
  update-position
  update-networth

  
  ; stock exchange procedures  
  set total-dealed-volume 0
  ask stocks [
    collect-bids-and-make-deal
    update-stock-price
  ]
  update-market-yield

  tick
end



;------------------------------------------------;
;----------------- GO SUBRUTINES ----------------;
;------------------------------------------------;
to setup-investors [number-investors] 
  create-investors number-investors
  [
    setxy random-xcor -10
    set strategy one-of (list "fundamental" "technique")
    set color one-of [blue red]
    set incoming-queue []
    let random-10-list (list random 10 random 10 random 10 random 10 random 10 random 10 random 10 random 10)
    set expectations sublist random-10-list 0 (count stocks) 
    set networth [ ]
  ]
  
  update-expectations "generate-price-random"
end


to investor-go-using-gp
  let tick-count 10
  while [tick-count > 0] [
    market-go "gp-employ"
    set tick-count tick-count - 1
  ]  
end


to update-expectations [run-option]
  
  if run-option = "generate-price-random"  [ 
    ask Investors [
      set expectations map [ [price] of ? + random 3 - random 2 ] sort-on [who] Stocks 
    ]
  ]
  
  if run-option = "gp-learn" [    ; usding gp-code to generate expectations
    foreach (sort-on [who] Stocks) [ gp-learn-strategy ? ]
  ]

  if run-option = "gp-employ" [
    ask Investors [
      let code [expectation] of one-of codeturtles with [ gp-fitness = gp-best-fitness-this-gen ]
    ]
  ]
  
  
end


to gp-learn-strategy [des-stock]
  if ticks < 100 [stop]
  
  set gp-current-stock des-stock
  
  set train-hist-price sublist [hist-price] of gp-current-stock (ticks - 100) (ticks - 10) ; use 0 - 100 to train, 90 - 100 to testify
  set test-hist-price sublist [hist-price] of gp-current-stock (ticks - 10) ticks   
  let max-learning-step 20
  let l-step 0
  
  gp-setup
  set gp-best-fitness-this-gen min [ gp-raw-fitness ] of codeturtles
  while [(gp-best-fitness-this-gen > 0.1) and (l-step < max-learning-step) ] [
    ;gp procedure
    gp-go
    ask codeturtles [
      set ycor expectation
      if expectation - stock-price 10 > max-pycor [ set ycor max-pycor ]
      if expectation - stock-price 10 < min-pycor [ set ycor min-pycor ]
    ]
    
    set l-step l-step + 1
  ]
    
end




to calculate-portfolio-adj
  ; just for test
  ask Investors [
    set portfolio-adj (map [ ifelse-value (?2 > [price] of ?1) [ 1 ][ -1 ] ] 
      (sort-on [who] Stocks) expectations portfolio )
  ]
end

to update-networth
  ask Investors [
    set networth lput (money + sum ( map [ ?1 * [price] of ?2 ] portfolio sort stocks )) networth
  ]
end






;; 
to make-bidding
  
  ; need to further consider optimized order-price!!!
  ;
  ask Investors [
    (foreach (sort-on [who] Stocks) portfolio-adj expectations [
      if ?2 > 0 
      [
        send-order "bl" [who] of ?1 ?3 ?2 ; [ "buy-limit" stock-name bidding-price #share ]
        set ?2 0
        ]
      if ?2 < 0 
      [
        send-order "sl" [who] of ?1 ?3 (- ?2) ; [ "sell-limit" stock-name bidding-price #share ]
        set ?2 0
        ]
    ])
  ]
end


to send-order [performative stock-id bidding-price num-shares]
  if performative = "bl" [ 
    let msg add-content (list bidding-price num-shares) create-message "bl" 
    send add-receiver stock-id msg
  ]
  if performative = "sl" [
    let msg add-content (list bidding-price num-shares) create-message "sl" 
    send add-receiver stock-id msg
  ]
end


to update-position
  ask Investors [
    let msg 0
    let performative 0
    while [not empty? incoming-queue]
    [
       set msg get-message  ;;["buy-order-executed" "sender:2" "content:" [10 1] "receiver:6"]
       set performative get-performative msg
       let content get-content msg      ;; [10 1]
       let dealed-price first content  ;; 10
       let exchange-informed-dealed-volume last content  ;; 1
       let s get-sender msg  ;; (who number) 2
     
       if performative = "buy-order-executed"
       [
         ;replace-item index list value 
         set portfolio replace-item (read-from-string s) portfolio (item read-from-string s portfolio + exchange-informed-dealed-volume)
         ]
       if performative = "sell-order-executed" 
       [ 
         set portfolio replace-item (read-from-string s) portfolio (item read-from-string s portfolio - exchange-informed-dealed-volume)
         ]
     ]
  ]
end


to allocate-money
  let m 0
  let d 1
  ifelse initial-average-wealth > global-wealth * 4
  [set m initial-average-wealth]
  [set m global-wealth * 4]
  set d m / 10
  if initial-wealth-distribution = "constant" [set money m]
  if initial-wealth-distribution = "normal" [set money round(random-normal m d)]
  if initial-wealth-distribution = "uniform" [set money round( m * 3 / 4 + random-float (1 / 2 * m))]
  if initial-wealth-distribution = "pareto" [set money round((m * 0.9) / ((random-float 1) ^ (1 / 5)))]  
  if initial-wealth-distribution = "lognormal" 
  [set money round(exp(ln(m) - (1 / 2) * ln(1 + (d / m) ^ 2) + (random-normal 0 1) * (ln(1 + (d / m) ^ 2)) ^ (1 / 2)))]
  set money_initial money
end


to-report total-return [time0]
  report last networth / (item (ticks - time0) networth)
end
@#$#@#$#@
GRAPHICS-WINDOW
233
10
478
468
10
20
10.43
1
10
1
1
1
0
1
1
1
-10
10
-20
20
1
1
1
Períod
30.0

BUTTON
1
279
73
337
Setup
Setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
75
279
179
338
generate-prices
generate-stock-historical-prices
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
7
17
185
50
Investor-population
Investor-population
1
100
10
1
1
NIL
HORIZONTAL

PLOT
757
11
1001
154
Price
NIL
NIL
0.0
10.0
0.0
20.0
true
false
"" ""
PENS
"default" 1.0 0 -8053223 true "" "plot [price] of first (sort-on [who] stocks)"
"pen-1" 1.0 0 -955883 true "" "if count stocks > 1 [plot [price] of item 1 (sort-on [who] stocks)]"
"pen-2" 1.0 0 -14454117 true "" "if count stocks > 2 [plot [price] of item 2 (sort-on [who] stocks)]"
"pen-3" 1.0 0 -7500403 true "" "if count stocks > 3 [plot [price] of item 3 (sort-on [who] stocks)]"
"pen-4" 1.0 0 -2674135 true "" "if count stocks > 4 [plot [price] of item 4 (sort-on [who] stocks)]"
"pen-5" 1.0 0 -6459832 true "" "ifelse ticks > 50 [plot [p_lin_5] of stock 0][plot [price] of stock 0]"
"pen-6" 1.0 0 -1184463 true "" "ifelse ticks > 50 [plot [p_com_5] of stock 0][plot [price] of stock 0]"

PLOT
758
150
1003
272
total dealed volume
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"pen-0" 1.0 0 -7500403 true "" "plot sum [dealed-volume] of stocks"

BUTTON
30
366
144
411
go-gp-learn
gp-learn-strategy stock 0
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
7
95
151
128
show_messages?
show_messages?
1
1
-1000

PLOT
1002
12
1254
151
total-market-value
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"total-market-value" 1.0 0 -5298144 true "" "if ticks > 10 \n[plot sum [last networth] of investors]"

PLOT
1002
151
1255
273
mean and max of return
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"benchmark-yield-market" 1.0 0 -2674135 true "" "plot market-mean-yield"
"plot benchmark-yield-max" 1.0 0 -13345367 true "" "plot market-max-yield"

INPUTBOX
8
141
148
201
initial-average-wealth
100
1
0
Number

OUTPUT
478
10
748
465
12

SLIDER
9
214
181
247
num-stocks
num-stocks
1
8
1
1
1
NIL
HORIZONTAL

INPUTBOX
937
297
1016
357
randomseed
1
1
0
Number

SWITCH
757
297
927
330
fix-random-seed?
fix-random-seed?
1
1
-1000

INPUTBOX
1020
297
1119
357
population-size
10
1
0
Number

INPUTBOX
755
360
886
420
initial-code-max-depth
3
1
0
Number

INPUTBOX
887
361
985
421
branch-chance
10
1
0
Number

INPUTBOX
987
361
1077
421
clone-chance
10
1
0
Number

INPUTBOX
1078
361
1166
421
mutate-chance
10
1
0
Number

INPUTBOX
1167
360
1269
420
crossover-chance
20
1
0
Number

PLOT
757
425
957
545
Fitness Plot
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"avg" 1.0 0 -16777216 true "" ""
"best" 1.0 0 -13840069 true "" ""
"worst" 1.0 0 -7500403 true "" ""

BUTTON
963
495
1066
528
NIL
gp-showbest
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
963
455
1062
488
show code
clear-output\nask one-of codeturtles [ \n  output-print gp-compiledcode \n  ]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
30
422
177
455
NIL
investor-go-using-gp
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## Where I can find more information?



## CREDITS AND REFERENCES

If you want to use this model, you have to quote the author: Gil, Alvaro. Artificial Stock Market. Pontificia Universidad Javeriana (Colombia) 2012. alvaro.gil@polymtl.ca
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person student
false
0
Polygon -13791810 true false 135 90 150 105 135 165 150 180 165 165 150 105 165 90
Polygon -7500403 true true 195 90 240 195 210 210 165 105
Circle -7500403 true true 110 5 80
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Polygon -1 true false 100 210 130 225 145 165 85 135 63 189
Polygon -13791810 true false 90 210 120 225 135 165 67 130 53 189
Polygon -1 true false 120 224 131 225 124 210
Line -16777216 false 139 168 126 225
Line -16777216 false 140 167 76 136
Polygon -7500403 true true 105 90 60 195 90 210 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
0
Rectangle -7500403 true true 151 225 180 285
Rectangle -7500403 true true 47 225 75 285
Rectangle -7500403 true true 15 75 210 225
Circle -7500403 true true 135 75 150
Circle -16777216 true false 165 76 116

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="Investor-population">
      <value value="10"/>
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Growth?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show_messages?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-average-wealth">
      <value value="100"/>
      <value value="200"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
