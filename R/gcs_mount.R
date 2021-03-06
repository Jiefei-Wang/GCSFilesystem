#' Mount a Google Cloud Storage(GCS) file system
#' 
#' The function uses the command-line program `GCSDokan` 
#' on Windows or `gcsfuse` on Linux system to mount 
#' a google cloud bucket path to your local file system.
#' 
#' @param remote the remote path to a Google Cloud Storage bucket.
#' It can be either the bucket itself or a directory in the bucket.
#' @param mountpoint The mount point where the GCS file system will
#' be mounted to.
#' @param mode the permission of the mounted directory. The write
#' permission is only available on Linux.
#' @param cache_type The location where the file cache will be
#' stored. The cache type `none` and `memory` are only available
#' on Windows
#' @param cache_arg The argument of a cache type. If 
#' `cache_type = "memory"`, the argument is the limit of
#' the memory useage in MB. If `cache_type = "disk"`, the 
#' argument is the path to a cache directory. 
#' @param billing The billing project ID. 
#' @param refresh The refresh rate of the cloud files.
#' @param implicit_dirs Implicitly define directories based on content.
#' This argument is only available on Linux.
#' @param key_file The service account credentials file
#' @param additional_args The additional argument that will be passed to
#' the command-line program.
#' @return no return value
#' @examples
#' bucket <- "genomics-public-data"
#' mountpoint <- paste0(tempdir(),"/GCSFilesystemTest")
#' ## You must have a credentials on Linux and macOs
#' ## To run this code
#' if(Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS")!=""){
#'     gcs_mount(bucket, mountpoint)
#'     gcs_unmount(mountpoint)
#' }
#' @export
gcs_mount <- function(remote, mountpoint, mode = c("r", "rw"), 
                      cache_type = c("disk", "memory", "none"),
                      cache_arg = NULL ,
                      billing = NULL, refresh = 60,
                      implicit_dirs = TRUE, key_file = NULL, 
                      additional_args = NULL){
    if(!check_required_program()){
        return()
    }
    mode <- match.arg(mode)
    cache_type <- match.arg(cache_type)
    
    mountpoint <- normalizePath(mountpoint, winslash = "/", 
                                mustWork = FALSE)
    ## Create the mountpoint folder if it does not exist
    check_dir(mountpoint)
    if(!is.null(cache_arg)&&
       cache_type=="disk"){
        cache_arg <- normalizePath(cache_arg, winslash = "/", 
                                    mustWork = FALSE)
        check_dir(cache_arg)
    }
    os <- get_os()
    ## remove "gs://" prefix
    if(startsWith(remote,"gs://")){
        remote <- substring(remote, 6)
    }
    
    args <- list(remote = remote, mountpoint = mountpoint, mode = mode,
                 cache_type = cache_type , cache_arg = cache_arg,
                 billing = billing, refresh = refresh,
                 implicit_dirs = implicit_dirs,
                 key_file = key_file,additional_args = additional_args)
    if(os == "windows"){
        do.call(gcs_mount_win, args)
    }else if(os == "linux"){
        do.call(gcs_mount_linux, args)
    }else if(os == "osx"){
        do.call(gcs_mount_linux, args)
    }else{
        stop("Unsupported system")
    }
    invisible()
}

gcs_mount_win <- function(remote, mountpoint, mode = c("rw", "r"), 
                          cache_type = "memory",
                          cache_arg = NULL ,
                          billing = NULL, refresh = 60,
                          implicit_dirs = TRUE, key_file = NULL, 
                          additional_args = NULL){
    args <- c()
    ## Load the credentials file if needed
    if(!is.null(key_file)){
        args <- c(args, paste0("--key \"", key_file,"\""))
    }
    
    if(cache_type=="disk"){
        args <- c(args, "--diskCache")
        if(!is.null(cache_arg)){
            args <- c(args, paste0("\"", cache_arg,"\""))
        }
    }else if(cache_type=="memory"){
        args <- c(args, "--memoryCache")
        if(!is.null(cache_arg)){
            args <- c(args, cache_arg)
        }
    }else{
        args <- c(args, "--noCache")
    }
    if(!is.null(billing)){
        args <- c(args, paste0("--billing ", billing))
    }
    ## Refresh rate
    args <- c(args, paste0("--refresh ", refresh))
    
    args <- c(args, additional_args)
    if(mode == "r"){
    }else{
        ## mode == "rw"
        stop("The file writting is not supported on Windows.")
    }
    args <- c(paste0("\"", remote, "\""), 
              paste0("\"", mountpoint, "\""),
              args)
    system2("GCSDokan", args, wait = FALSE)
}


gcs_mount_linux <- function(remote, mountpoint, mode = c("rw", "r"), 
                            cache_type = "disk",
                            cache_arg = NULL ,
                            billing = NULL, refresh = 60,
                            implicit_dirs = TRUE, key_file = NULL, 
                            additional_args = NULL){
    ## Determine if the folder-like structure will be used
    if(implicit_dirs){
        args <- "--implicit-dirs"
    }else{
        args <- character()
    }
    ## Load the credentials file if needed
    if(!is.null(key_file)){
        args <- c(args, paste0("--key-file \"", key_file,"\""))
    }
    
    if(cache_type!="disk"){
        stop("gcsfuse only supports disk cache")
    }
    if(!is.null(cache_arg)){
        args <- c(args, paste0("--temp-dir \"", cache_arg,"\""))
    }
    if(!is.null(billing)){
        args <- c(args, paste0("--billing-project ", billing))
    }
    ## Refresh rate
    args <- c(args, paste0("--stat-cache-ttl ", refresh,"s"))
    args <- c(args, paste0("--type-cache-ttl ", refresh,"s"))
    
    args <- c(args, additional_args)
    if(mode == "r"){
        file_mode <- "444"
        dir_mode <- "555"
    }else{
        ## mode == "rw"
        file_mode <- "644"
        dir_mode <- "755"
    }
    args <- c(args, "--dir-mode", dir_mode, "--file-mode", file_mode)
    
    ## decompose the remote path and pass the bucket
    ## and path to gcsfuse separately
    remote_component <- unlist(strsplit(remote, "/", fixed = TRUE))
    bucket <- remote_component[1]
    path_in_bucket <- paste0(remote_component[-1], collapse = "/")
    if(path_in_bucket != ""){
        args <- c(args, paste0("--only-dir \"", path_in_bucket, "\""))
    }
    
    args <- c(args, 
              paste0("\"", bucket, "\""), 
              paste0("\"", mountpoint, "\"")
              )
    system2("gcsfuse", args)
}