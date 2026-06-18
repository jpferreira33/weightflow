# Names used via non-standard evaluation (glm/rpart weights & response inside
# fitted models). Declared here so R CMD check does not flag them as undefined
# global variables.
utils::globalVariables(c(".wts", ".y"))
