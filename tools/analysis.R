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
    if (is.na(val) || is.nan(val) || is.infinite(val))
        return(style(toString(val),"red"))

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

    # We are outside of the defined thresholds
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
                if (elem[[1]] %in% names(list(...)))
                    curval <- curval * (list(...)[[elem[1]]] ^ as.numeric(elem[2]))
                else
                    cat("Missing argument to solve_eqn: ", elem[[1]], "\n")
            } else {
                if (prod %in% names(list(...)))
                    curval <- curval * list(...)[[prod]]
                else
                    cat("Missing argument to solve_eqn: ", prod, "\n")
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
bench <- read_delim(args[1], ";", escape_double = FALSE, trim_ws = TRUE,col_types = cols(`cpu-cycles`="d", `cpu-cycles-ref`="d", instructions="d", `branch-events`="d", `cache-events`="d", `memory-events`="d", `avx-events`="d"))

prefilter <- Sys.getenv("PREFILTER",unset=NA)
if (!is.na(prefilter)) {
    pre <- NROW(bench)
    cat("Filtering data\n")
    bench <- sqldf(prefilter)
    cat("Removed ",pre-NROW(bench)," of ",pre," entries\n")
}


# Select benches from environment variable 'BENCHES' if applicable
benches <- Sys.getenv("BENCHES",names=TRUE,unset=NA)
benches_exclude <- Sys.getenv("BENCHES_EXCLUDE",names=TRUE,unset=NA)
if (!is.na(benches)) {
    benches <- unlist(strsplit(benches,","))
} else {
    benches <- unlist(sqldf("SELECT DISTINCT bench FROM bench")["bench"])
}

if (!is.na(benches_exclude)) {
    benches <- setdiff(benches,unlist(strsplit(benches_exclude,",")))
}

bench <- sqldf(paste0("SELECT * FROM bench WHERE bench IN (",paste(sprintf("'%s'",benches),collapse=","),")"))


bench <- within(bench, {
    IPC <- instructions/(`cpu-cycles`/cpus)
    ht <- ifelse(ht == "enable", 1, 0)

    # 'cache-events' counts everything that contains the cache, but we are only interested in cache hits
    `cache-hits` <- `cache-events` - `memory-events`

    # calculate the heaviness of the applications
    memory_heaviness <- `memory-events`/instructions
    nomemory_heaviness <- 1-memory_heaviness
    cache_heaviness <- `cache-hits`/instructions
    avx_heaviness <- `avx-events`/instructions
    branch_heaviness <- `branch-events`/instructions
    compute_heaviness <- (instructions - `cache-hits` - `memory-events` - `avx-events` - `branch-events`)/instructions

    # calculate the power consumption
    power_ram <- `power/energy-ram/`/`t_diff`
    power_cores <- `power/energy-cores/`/`t_diff`
    power_pkg <- `power/energy-pkg/`/`t_diff`
})

m_IPC <- lm(IPC ~
                poly(memory_heaviness,2,raw=TRUE)*cpus*freq +
                poly(cache_heaviness,2,raw=TRUE)*cpus*freq +
                poly(compute_heaviness,2,raw=TRUE)*cpus*freq +
                poly(avx_heaviness,2,raw=TRUE)*cpus*freq +
#                poly(freq,2,raw=TRUE) +
#                poly(cpus,2,raw=TRUE) +
                ht,
            data=bench)
sm_IPC <- summary(m_IPC)
print(sm_IPC)

m_power_cores <- lm(power_cores ~
                nomemory_heaviness*poly(freq,2,raw=TRUE)*cpus*IPC, 
#                avx_heaviness*freq*cpus
#                IPC +
#                poly(freq,3,raw=TRUE) +
#                cpus
#                ht,
            ,data=bench)
sm_power_cores <- summary(m_power_cores)
print(sm_power_cores)

m_power_ram <- lm(power_ram ~
                memory_heaviness*IPC *
                 freq*cpus
            ,data=bench)
sm_power_ram <- summary(m_power_ram)
print(sm_power_ram)

m_power <- lm(power_pkg ~
                memory_heaviness*poly(freq,2,raw=TRUE)*cpus*IPC 
#                poly(freq,3,raw=TRUE) +
#                cpus# +
#                ht
            ,data=bench)
sm_power <- summary(m_power)
print(sm_power)

#Solve it
bench <- within(bench, {
    IPC_modeled <- solve_eqn(sm_IPC, memory_heaviness=memory_heaviness, cache_heaviness=cache_heaviness, ht=ht, freq=freq, compute_heaviness=compute_heaviness, avx_heaviness=avx_heaviness, cpus=cpus)
    IPC_abserr_rel <- abs(IPC_modeled - IPC) / IPC
    power_modeled <- solve_eqn(sm_power, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_abserr_rel <- abs(power_modeled - power_pkg) / power_pkg
    power_modeled_ripc <- solve_eqn(sm_power, IPC=IPC, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_abserr_rel_ripc <- abs(power_modeled_ripc - power_pkg) / power_pkg
    power_modeled_ram <- solve_eqn(sm_power_ram, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_abserr_rel_ram <- abs(power_modeled_ram - power_ram) / power_ram
    power_modeled_ram_ripc <- solve_eqn(sm_power_ram, IPC=IPC, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_abserr_rel_ram_ripc <- abs(power_modeled_ram_ripc - power_ram) / power_ram
    power_modeled_cores <- solve_eqn(sm_power_cores, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,nomemory_heaviness=nomemory_heaviness,avx_heaviness=avx_heaviness)
    power_abserr_rel_cores <- abs(power_modeled_cores - power_cores) / power_cores
    power_modeled_cores_ripc <- solve_eqn(sm_power_cores, IPC=IPC, freq=freq, ht=ht, cpus=cpus,nomemory_heaviness=nomemory_heaviness,avx_heaviness=avx_heaviness)
    power_abserr_rel_cores_ripc <- abs(power_modeled_cores_ripc - power_cores) / power_cores
})

cat("IPC = "); print_eqn(sm_IPC)
cat("P_pkg = "); print_eqn(sm_power)
cat("P_ram = "); print_eqn(sm_power_ram)
cat("P_cores = "); print_eqn(sm_power_cores)

colors = c("green","yellow","white","magenta","red")
thresholds=c(0.05,0.07,0.1,0.15,1.0)

cat('Datapoints as basis for models and evaluation: ',nrow(bench),"\n")
cat(style("columns denoted with ' use real IPC values, not modeled ones\n\n","green"))

metrics <- c("IPC","P_PKG","P_CORES","P_RAM","P_PKG'","P_CORES'","P_RAM'")
metric_columns <- c("IPC_abserr_rel","power_abserr_rel","power_abserr_rel_cores","power_abserr_rel_ram",
                "power_abserr_rel_ripc","power_abserr_rel_cores_ripc","power_abserr_rel_ram_ripc")

cat(rep(" ",12),sep="")
for (m in metrics) {
    cat(sprintf(" %-8s",m))
}
cat("\n")

for (b in benches) {
    cat(sprintf("%-10s:",b))
    for (m in metric_columns) {
        cat(" ",colorprint(sprintf("%7s",sprintf("%2.4f",mean(sqldf(paste('select * from bench where bench == "',b,'"',sep=""))[[m]]))),thresholds,colors,FALSE))
    }
    cat("\n")
}
cat("MAPE (all):")
for (m in metric_columns) {
    cat(" ",colorprint(sprintf("%7s",sprintf("%2.4f",mean(bench[[m]]))),thresholds,colors,FALSE))
}
cat("\n")

write.csv(bench, "r_data.csv")
