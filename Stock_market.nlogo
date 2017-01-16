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
extensions [matrix stats csv web time]

breed [Stocks stock]
breed [Investors investor]

__includes ["communication.nls" "bidding.nls" "stockexchange.nls" "gp.nls"]

globals [
  global-wealth
  initial-wealth-distribution
  h-prices
  total-dealed-volume
  dividends  ; intrinsic value, imported by .csv
  max-networth
  data
]


turtles-own [ incoming-queue ]           ; for communication


Investors-own [
  informed?
  money_initial             ;
  money
  networth
  shares-dealed-tick
  portfolio
  watch-agent
  strategy
  expectation
  l-freq       ;learning-frequency - 控制Investor学习时机
  init-l-freq
]





to setup
  clear-all
  ask patches [set pcolor black]

  setup-stocks 1
  set gp-current-stock stock 0
  set h-prices []
  reset-ticks

  set-default-shape turtles "Person"
  setup-investors Investor-population

  set global-wealth sum [money] of investors
  ;; temporally remove chooser ""initial-wealth-distribution", to run online demo which cannot read string input
  set initial-wealth-distribution "normal"
  ;;
  ask investors [
    allocate-money
    set l-freq 2 + random 8   ; 1 to 30
    set init-l-freq l-freq
    update-networth
  ]
end


; run-options:
;    - generate-price steps - generate historical prices with previous investing strategy
;    - gp-learn             - learning new investing strategy using historical stock prices
;
to go
  ; investors procedures
  update-expectation
  make-bidding

  ; stock exchange procedures
  set total-dealed-volume 0
  ask Stocks [
    collect-bids-and-make-deal
    update-stock-tables
    set h-prices lput price h-prices
  ]

  ; investors procedures
  update-position
  update-networth

  if ticks >= initial-random-walk-steps [
    if not any? codeturtles [gp-setup]
    gp-go
  ]
  if ticks >= length dividends - 1 [stop]
  tick
end


;------------------------------------------------;
;----------------- GO SUBRUTINES ----------------;
;------------------------------------------------;
to setup-investors [number-investors]
  create-investors number-investors
  [
    set color black
    setxy random-xcor random-ycor
    set incoming-queue []
    set expectation [price] of stock 0 + random 10 - random 10
;    set networth [ ]
  ]

  ask n-of (noise-ratio / 100 * count investors) investors [ set color white ]
  ask n-of (%-informed / 100 * count investors with [color != white]) investors with [color != white][set informed? true   set color blue ]
  ask investors with [color = black][ set informed? false   set color red  ]
  update-expectation
end



to update-expectation
  ask Investors [
    ifelse color = white
    [ set expectation [ round (intr-value) + random 5 - random 5 ] of stock 0 ]     ; noise investors
    [
      ifelse ticks < initial-random-walk-steps + who
      [ set expectation [price + random 5 - random 5 ] of Stock 0 ]
      [
        ifelse (l-freq = 0 or watch-agent = 0) [
          set l-freq init-l-freq
          update-strategy
        ][ set l-freq l-freq - 1 ]
      if strategy != 0 [ run strategy set expectation round expectation]
    ] ]
  ]
  update-ycor
end


to update-ycor
  ask Investors [
    let new-pos expectation / max [expectation] of Investors  * max-pycor * 0.9
    set ycor ifelse-value (new-pos > 0) [ new-pos] [0]
  ]
end


to update-strategy
  ask Investors with [color = red][
    ; uninformed investor can choose strategies without intr-value
    if any? codeturtles with [not member? "intr-value" gp-compiledcode][
      set watch-agent min-one-of codeturtles with [not member? "intr-value" gp-compiledcode] [ gp-calculate-fitness [init-l-freq] of myself ]
      set strategy [gp-compiledcode] of watch-agent
    ]
  ]
  ask Investors with [color = blue][
    if any? codeturtles [
      set watch-agent min-one-of codeturtles [ gp-calculate-fitness [init-l-freq] of myself ]
      set strategy [gp-compiledcode] of watch-agent
    ]
  ]
end



to update-networth
  ask Investors [
    set networth money + portfolio * [price] of stock 0
  ]
  set max-networth max [networth] of Investors
end



;;
to make-bidding
  ask Investors [
    if (expectation - [price] of stock 0) / [price] of stock 0 > 0.05 and money >= [price] of stock 0 [
      send-order one-of (list "bl" "bm") 0 (round ([price] of stock 0 + (random abs (expectation - [price] of stock 0)))) 1 ; [ "buy-limit" stock-name order-price #share ]
    ]
    if (expectation - [price] of stock 0) / [price] of stock 0 < -0.05 [
      send-order one-of (list "sl" "sm") 0 (round ([price] of stock 0 - (random abs (expectation - [price] of stock 0)))) 1 ; [ "sell-limit" stock-name order-price #share ]
    ]
  ]
end


to send-order [performative stock-id order-price num-shares]
  if performative = "bl" [
    let msg add-content (list order-price num-shares) create-message "bl"
    send add-receiver stock-id msg
  ]
  if performative = "bm" [  ; buy market order
    let msg add-content (list order-price  num-shares) create-message "bl"
    send add-receiver stock-id msg
  ]
  if performative = "sl" [  ; sell limit order
    let msg add-content (list order-price num-shares) create-message "sl"
    send add-receiver stock-id msg
  ]
  if performative = "sm" [  ; sell market order
    let msg add-content (list order-price num-shares) create-message "sl"
    send add-receiver stock-id msg
  ]

end


to update-position
  ask Investors [
    set shares-dealed-tick 0
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
      set shares-dealed-tick shares-dealed-tick + last content

      if performative = "buy-order-executed"
      [
        ;replace-item index list value
        set portfolio portfolio + exchange-informed-dealed-volume
        set money money - dealed-price * exchange-informed-dealed-volume
      ]
      if performative = "sell-order-executed"
      [
        set portfolio portfolio - exchange-informed-dealed-volume
        set money money + dealed-price * exchange-informed-dealed-volume
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
@#$#@#$#@
GRAPHICS-WINDOW
225
17
470
380
5
-1
15.82
1
10
1
1
1
0
0
0
1
-5
5
0
20
1
1
1
Períod
30.0

BUTTON
1
327
73
385
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
327
216
386
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
6
17
207
50
Investor-population
Investor-population
1
100
100
1
1
NIL
HORIZONTAL

PLOT
693
10
1259
153
Price
NIL
NIL
0.0
10.0
0.0
20.0
true
true
"" "if ticks > 200 [set-plot-x-range (ticks - 200) ticks]"
PENS
"price" 1.0 0 -8053223 true "" "plot [price] of Stock 0"
"intrinsic-value" 1.0 0 -7500403 true "" "plot dividend ticks / r * 100"

PLOT
693
150
1259
287
Trading Volume
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" "if ticks > 200 [set-plot-x-range (ticks - 200) ticks]"
PENS
"noise-investor" 1.0 0 -7500403 true "" "plot sum [dealed-volume] of stocks"
"uninformed" 1.0 0 -2674135 true "" "plot sum [shares-dealed-tick] of investors with [color = red]"
"informed" 1.0 0 -13791810 true "" "plot sum [shares-dealed-tick] of investors with [color = blue]"

BUTTON
76
388
190
433
go
go
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
143
151
176
show_messages?
show_messages?
1
1
-1000

INPUTBOX
8
189
148
249
initial-average-wealth
1000
1
0
Number

INPUTBOX
1018
307
1097
367
randomseed
2
1
0
Number

SWITCH
1107
300
1277
333
fix-random-seed?
fix-random-seed?
1
1
-1000

INPUTBOX
913
306
1012
366
population-size
10
1
0
Number

INPUTBOX
695
371
826
431
initial-code-max-depth
5
1
0
Number

INPUTBOX
827
372
925
432
branch-chance
5
1
0
Number

INPUTBOX
927
372
1017
432
clone-chance
10
1
0
Number

INPUTBOX
1018
372
1106
432
mutate-chance
10
1
0
Number

INPUTBOX
1107
371
1209
431
crossover-chance
10
1
0
Number

PLOT
823
437
1023
557
Fitness Plot
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" "if ticks > 200 [set-plot-x-range (ticks - 200) ticks ]"
PENS
"avg" 1.0 0 -16777216 true "" ""
"best" 1.0 0 -13840069 true "" ""
"worst" 1.0 0 -2674135 true "" ""

BUTTON
701
523
804
556
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
701
483
815
516
show all code
clear-output\nask codeturtles with [length gp-compiledcode > 6][ \n  output-print self \n  output-print gp-compiledcode \n  output-print \"----------\"\n  ]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1160
86
1259
131
NIL
[price] of Stock 0
17
1
11

PLOT
426
16
686
136
investor expectations
NIL
NIL
0.0
150.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "" "if ticks > 1 and any? investors [\nset-plot-x-range (min [expectation] of investors)(max[expectation] of investors)\nhistogram [expectation] of Investors\n]"

SLIDER
6
87
208
120
%-informed
%-informed
0
100
39
1
1
NIL
HORIZONTAL

INPUTBOX
9
257
169
317
initial-random-walk-steps
100
1
0
Number

INPUTBOX
8
512
96
572
file-choose
sh.csv
1
0
String

SWITCH
1106
337
1247
370
show-debug?
show-debug?
1
1
-1000

SLIDER
6
52
207
85
noise-ratio
noise-ratio
0
100
41
1
1
NIL
HORIZONTAL

INPUTBOX
693
307
815
367
max-learning-step
130
1
0
Number

PLOT
427
138
687
258
codeturtle expectations
NIL
NIL
0.0
150.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "" "if ticks > initial-random-walk-steps and any? codeturtles [\nset-plot-x-range (min [expectation] of codeturtles) (max [expectation] of codeturtles)\nhistogram [expectation] of codeturtles]"

INPUTBOX
818
307
911
367
max-popsize
200
1
0
Number

MONITOR
695
435
818
480
NIL
count codeturtles
17
1
11

PLOT
426
260
687
380
networth distribution
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
"default" 1.0 1 -16777216 true "" "if any? investors [\nset-plot-x-range (min [networth] of investors) (max [networth] of investors)\nhistogram [networth] of investors\n]"

SLIDER
204
540
296
573
r
r
0.01
0.1
0.1
0.01
1
%
HORIZONTAL

PLOT
434
388
695
552
best-yield-by-group
NIL
NIL
0.0
10.0
0.0
1.0
true
true
"" "if ticks > 100 [set-plot-x-range (ticks - 100) ticks]"
PENS
"noise-best" 1.0 0 -16777216 true "" "if ticks > 0 [plot max [networth / money_initial] of investors with [color = white]]"
"uninformed-best" 1.0 0 -2674135 true "" "if ticks > 0 [plot max [networth / money_initial] of investors with [color = red]]"
"informed-best" 1.0 0 -13345367 true "" "if ticks > 0 [plot max [networth / money_initial] of investors with [color = blue]]"
"noise-mean" 1.0 0 -9276814 true "" "if ticks > 0 [plot mean [networth / money_initial] of investors with [color = white]]"
"uninformed-mean" 1.0 0 -1604481 true "" "if ticks > 0 [plot mean [networth / money_initial] of investors with [color = red]]"
"informed-mean" 1.0 0 -10649926 true "" "if ticks > 0 [plot mean [networth / money_initial] of investors with [color = blue]]"

INPUTBOX
97
512
187
572
code
sh600519
1
0
String

CHOOSER
5
466
194
511
data-source
data-source
"from-file" "webAPI" "monte-carlo"
1

INPUTBOX
196
388
434
531
cross_fitness_weight
[0.1 0.1 0.1 0.1 0.1 0.1 0 0 0 0.4\n]
1
1
String

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
NetLogo 5.3.1
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
