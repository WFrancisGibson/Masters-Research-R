##########################################
#########  run all checks of tests/testthat
#########  from the project root: Rscript tests/testthat.R
##########################################

testthat::test_dir(here::here("tests", "testthat"))
