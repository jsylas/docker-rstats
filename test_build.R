# Loosely based on http://www.kdnuggets.com/2015/06/top-20-r-packages.html

expectGPU <- Sys.getenv("EXPECT_GPU") == "1"

Library <- function(libname){
  print(libname)
  suppressPackageStartupMessages(library(libname, character.only=TRUE))
}

# TODO(seb): Figure out why h2o4gpu fails to load when done following the
# keras_model_sequential() statement.
Library("h2o4gpu")
Library("keras")
print("Testing keras-python connection")
m <- keras_model_sequential()
Library("Rcpp")
Library("gapminder")
Library("gganimate")
Library("ggplot2")
Library("stringr")
Library("plyr")
Library("digest")
Library("reshape2")
Library("colorspace")
Library("RColorBrewer")
Library("scales")
Library("labeling")
Library("proto")
Library("munsell")
Library("gtable")
Library("dichromat")
Library("mime")
Library("RCurl")
Library("bitops")
Library("zoo")
Library("knitr")
Library("dplyr")
Library("readr")
Library("tidyr")
Library("randomForest")
Library("xgboost")
Library("rstan")
Library("prophet")
Library("fftw")
Library("seewave")
Library("kmcudaR")
Library("bayesCL")
if (expectGPU) {
  Library("gpuR")
  detectGPUs()
  listContexts()
  set.seed(11111)
  gpuA <- gpuMatrix(rnorm(262144), nrow = 512, ncol = 512)
  gpuB <- gpuA %*% gpuA
  as.numeric(gpuB[1, 1]) == (32.51897782759634 + 7.105427e-15) # very high precision
}
library(reticulate)
lib_device <- reticulate::import(module = "tensorflow.python.client.device_lib", as = "lib_device")
lib_device$list_local_devices()
stopifnot(lib_device$list_local_devices()[[1]]$name == "/device:CPU:0")
if (expectGPU) {
  stopifnot(lib_device$list_local_devices()[[2]]$name == "/device:GPU:0")
}

testPlot1 <- ggplot(data.frame(x=1:10,y=runif(10))) + aes(x=x,y=y) + geom_line()
ggsave(testPlot1, filename="plot1.png")

# Test that base graphics will save to .png by default
plot(runif(10))

# Test gganimate.
testPlot2 <- ggplot(gapminder, aes(gdpPercap, lifeExp, size = pop, color = continent, frame = year)) +
  geom_point() +
  scale_x_log10()
testPlot2Animation <- gganimate(testPlot2, "plot2.gif")


print("Ok!")
