#!/usr/bin/env Rscript

# Install all the necessary packages
required.packages <- c("crayon","RSQLite","proto","gsubfn","readr","sqldf")
new.packages <- required.packages[!(required.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)
for (p in required.packages) {
  library(p,character.only =TRUE)
}

# Helper functions
colorprint <- function(val, thresholds, colors, greater = TRUE) {
    stopifnot(length(thresholds)==length(colors))
    for (i in 1:length(colors)) {
        if (greater) {
            if (val > thresholds[i]) {
                return(style(toString(val),colors[i]))
            }
        } else {
            if (val < thresholds[i]) {
                return(style(toString(val),colors[i]))
            }
        }
    }
    return(val)
}

print_eqn <- function(sum, prefix = "") {
    for (r in rownames(coef(sum))[2:length(rownames(coef(sum)))]) {
        cat(coef(sum)[r,"Estimate"])
        for (prod in strsplit(r,":")[[1]]) {
            cat(" * ")
            if (substr(prod,1,4) == "poly") {
                elem <- strsplit(sub("poly\\(([^,]+), [^\\)]+\\)([0-9]*)","\\1,\\2",prod, perl=TRUE),",")[[1]]
                cat(prefix,elem[1],sep="")
                cat(ifelse(elem[2] > 1,paste("**",elem[2],sep=""),""))
            } else {
                cat(prefix,prod,sep="")
            }
        }
        cat(" + ",sep="")
    }
    cat(coef(sum)["(Intercept)","Estimate"])

    colors = c("green","yellow","white","magenta","red")
    thresholds = c(0.9,0.8,0.7,0.6,0.0)
    cat(" [R² =",colorprint(sum$adj.r.squared,thresholds,colors,TRUE),"]\n")
}

solve_eqn <- function(sum,...) {
    tot_sum = 0
    for (r in rownames(coef(sum))[2:length(rownames(coef(sum)))]) {
        curval <- coef(sum)[r,"Estimate"]
        for (prod in strsplit(r,":")[[1]]) {
            if (substr(prod,1,4) == "poly") {
                elem <- strsplit(sub("poly\\(([^,]+), [^\\)]+\\)([0-9]*)","\\1,\\2",prod, perl=TRUE),",")[[1]]
                curval <- curval * (list(...)[[elem[1]]] ^ as.numeric(elem[2]))
            } else {
                curval <- curval * list(...)[[prod]]
            }
        }
        tot_sum <- tot_sum + curval
    }

    tot_sum <- tot_sum + coef(sum)["(Intercept)","Estimate"]
    return(tot_sum)
}

# Main
args = commandArgs(trailingOnly=TRUE)
if (length(args) == 0) {
    args[1] = "bench.csv"
}
bench <- read_delim(args[1], ";", escape_double = FALSE, trim_ws = TRUE,col_types = cols(`cache-misses`="d",`cpu-cycles`="d",`cache-references`="d",instructions="d"))

bench <- within(bench, {
    IPC <- instructions/`cpu-cycles`
    ht <- ifelse(ht == "enable", 1, 0)
    `memory_heaviness` <- `cache-misses`/instructions
    `cache-hits` <- `cache-references` - `cache-misses`
    `compute_heaviness` <- (instructions - `cache-hits` - `cache-misses`)/instructions
    `cache_heaviness` <- `cache-hits`/instructions
    `power-ram` <- `power/energy-ram/`/`t_diff`
    `power-cores` <- `power/energy-cores/`/`t_diff`
    `power-pkg` <- `power/energy-pkg/`/`t_diff`
})

m_IPC <- lm(IPC ~ memory_heaviness +
                poly(cache_heaviness,2,raw=TRUE) +
                poly(compute_heaviness,2,raw=TRUE) +
                frequency +
                ht,
            data=bench)
sm_IPC <- summary(m_IPC)

m_power <- lm(`power-pkg` ~ IPC +
                frequency +
                poly(cores,2,raw=TRUE) +
                ht,
            data=bench)
sm_power <- summary(m_power)

#Solve it
bench <- within(bench, {
    IPC_modeled <- solve_eqn(sm_IPC,memoryHeaviness = memoryHeaviness, cacheHeaviness = cacheHeaviness, ht = ht, avxHeaviness = avxHeaviness, frequency = frequency,computeHeaviness = computeHeaviness)
    IPC_abserr_rel <- abs(IPC_modeled - IPC) / IPC
    power_modeled <- solve_eqn(sm_power, frequency = frequency, IPC = IPC_modeled, cores = cores, ht = ht)
    power_abserr_rel <- abs(power_modeled - `power-pkg`) / `power-pkg`
})

print_eqn(sm_IPC)
print_eqn(sm_power)
for (b in c("bt.A", "cg.B", "dc.A", "ep.B", "ft.C", "is.C", "lu.B", "mg.C", "sp.B", "ua.A")) {
    cat("MAPE IPC (",b,"): ",colorprint(mean(sqldf(paste('select * from bench where bench == "',b,'"',sep=""))$IPC_abserr_rel),thresholds=c(0.02,0.05,0.1,0.2,1.0),colors,FALSE),"\n")
}
cat("MAPE IPC: ",colorprint(mean(bench$IPC_abserr_rel),thresholds=c(0.02,0.05,0.1,0.2,1.0),colors,FALSE),"\n")
cat("MAPE Power: ",colorprint(mean(bench$power_abserr_rel),thresholds=c(0.02,0.05,0.1,0.2,1.0),colors,FALSE),"\n")

