# print() output is stable

    Code
      print(snap_rec())
    Output
      
      == Weighting specification (weightflow) ==
      Data    : 467 cases
      Base wts: pw
      Steps   :
        1. nonresponse (weighting class)
        2. calibration (raking)
      Status  : estimated (prep)
      
      Stage summary:
                          stage n_active sum_wts cv_wts deff_kish n_eff
                           base      467    4371  0.236     1.056   442
       stage_1_step_nonresponse      270    4371  0.172     1.029   262
         stage_2_step_calibrate      270    4495  0.232     1.054   256
      
      deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
      n_eff = n_active / deff_kish. Both worsen with each adjustment and
      improve with trimming.
      

# summary() output (incl. the R-indicator line) is stable

    Code
      summary(snap_rec())
    Output
      
      == Weighting specification (weightflow) ==
      Data    : 467 cases
      Base wts: pw
      Steps   :
        1. nonresponse (weighting class)
        2. calibration (raking)
      Status  : estimated (prep)
      
      Stage summary:
                          stage n_active sum_wts cv_wts deff_kish n_eff
                           base      467    4371  0.236     1.056   442
       stage_1_step_nonresponse      270    4371  0.172     1.029   262
         stage_2_step_calibrate      270    4495  0.232     1.054   256
      
      deff_kish = 1 + CV^2 (Kish design effect from unequal weighting);
      n_eff = n_active / deff_kish. Both worsen with each adjustment and
      improve with trimming.
      
      --- Step 1: nonresponse (weighting class) ---
            cell n_respondents n_nonresponse   factor
        East | F            33            18 1.545455
        East | M            19            26 2.368421
       North | F            38            20 1.526316
       North | M            40            21 1.525000
       South | F            35            26 1.742857
       South | M            37            23 1.621622
        West | F            24            25 2.041667
        West | M            44            38 1.863636
      Kish deff: 1.056 -> 1.029   |   n_eff: 442 -> 262
      
      --- Step 2: calibration (raking) ---
       variable category target achieved
         region    North   1570     1570
         region    South   1250     1250
         region     East    927      927
         region     West    748      748
            sex        F   2311     2311
            sex        M   2184     2184
      (converged/iterated in 5 iterations)
      Kish deff: 1.029 -> 1.054   |   n_eff: 262 -> 256
      
      R-indicator (representativity of response): 0.890  (on region, sex)

# design_effect() output is stable

    Code
      str(design_effect(collect_weights(snap_rec())$.weight))
    Output
      List of 4
       $ deff : num 1.05
       $ n_eff: num 256
       $ cv   : num 0.232
       $ n    : int 270

