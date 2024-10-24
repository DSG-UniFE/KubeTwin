#!/usr/bin/Rscript

suppressMessages(library(VGAM))

# request generation is modeled with a Pareto distribution
# these values were chosen to generate roughly 6666.667 requests per second

# location 1.2E-4 --> 6666 rps
# location 3.7E-4 --> 2162 rps
# location 2.0E-4 --> 4000 rps
set.seed(123)
location            <- 3.7E-4
shape               <- 5
requests.per.second <- (shape - 1) / (shape * location)

# generate 2 minutes of requests

simulation.time <- 5 * 60

# number of requests
num.requests <- 0.4 * simulation.time * requests.per.second

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
customer.ids <- rep(1, length(generation.times))
#customer.ids  <- sample.int(num.customers, length(generation.times), replace=T)#,
                            #prob=c(0.4,0.2,0.4))

############ !!!!!!! INCREASING SPIKE !!!!!!!!!!!!! ###########

# start again with a different shape
first.request.time    <- tail(generation.times, n=1)

# this is a consistent spike from 2200 to 4000 rps
location <- 2.0E-4
requests.per.second <- (shape - 1) / (shape * location)

# 0.3 + 0.5 + 0.4 
num.requests <- 0.15 * simulation.time * requests.per.second

request.interarrival.times <- rpareto(num.requests, location, shape)
generation.times.2         <- diffinv(request.interarrival.times, xi=first.request.time)

# number of workflow types
num.workflow.types <- 2
# random workflow type id sequence
workflow.type.ids.2 <- sample.int(num.workflow.types, length(generation.times.2), replace=T,
                                prob=c(0.65,0.35))

# number of customers
num.customers <- 1
# random customer id sequence
customer.ids.2  <- rep(num.customers, length(generation.times.2))

# COOLDOWN

# start again with a different shape
first.request.time    <- tail(generation.times.2, n=1)

location <- 3.7E-4
requests.per.second <- (shape - 1) / (shape * location)

# 0.3 + 0.5 + 0.4 
num.requests <- 0.50 * simulation.time * requests.per.second

request.interarrival.times <- rpareto(num.requests, location, shape)
generation.times.3         <- diffinv(request.interarrival.times, xi=first.request.time)

# number of workflow types
num.workflow.types <- 2
# random workflow type id sequence
workflow.type.ids.3 <- sample.int(num.workflow.types, length(generation.times.3), replace=T,
                                prob=c(0.65,0.35))

# number of customers
num.customers <- 1
# random customer id sequence
customer.ids.3  <- rep(num.customers, length(generation.times.3))

generation.times <- c(generation.times, generation.times.2, generation.times.3)
workflow.type.ids <- c(workflow.type.ids, workflow.type.ids.2, workflow.type.ids.3)
customer.ids <- c(customer.ids, customer.ids.2, customer.ids.3)

df <- data.frame(Generation.Time  = generation.times,
                 Workflow.Type.ID = workflow.type.ids,
                 Customer.ID      = customer.ids)
write.csv(df[order(df$Generation.Time),], row.names=F)
