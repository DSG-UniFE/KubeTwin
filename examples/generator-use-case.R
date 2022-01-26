#!/usr/bin/Rscript

suppressMessages(library(VGAM))

# request generation is modeled with a Pareto distribution
# these values were chosen to generate roughly 6666.667 requests per second
location            <- 1.2E-4
shape               <- 5
requests.per.second <- (shape - 1) / (shape * location)

# generate 2 minutes of requests

simulation.time <- 2 * 60

# number of requests
num.requests <- 1.2 * simulation.time * requests.per.second

# request generation times
first.request.time         <- as.POSIXct(as.Date("28/5/2020", "%d/%m/%Y"))
request.interarrival.times <- rpareto(num.requests, location, shape)
generation.times           <- diffinv(request.interarrival.times, xi=first.request.time)

# number of workflow types
num.workflow.types <- 2
# random workflow type id sequence
workflow.type.ids <- sample.int(num.workflow.types, length(generation.times), replace=T,
                                prob=c(0.65,0.35))

# number of customers
num.customers <- 1
# random customer id sequence
customer.ids  <- sample.int(num.customers, length(generation.times), replace=T)#,
                            #prob=c(0.4,0.2,0.4))

# prepare data frame and output it on the console
df <- data.frame(Generation.Time  = generation.times,
                 Workflow.Type.ID = workflow.type.ids,
                 Customer.ID      = customer.ids)
write.csv(df[order(df$Generation.Time),], row.names=F)
