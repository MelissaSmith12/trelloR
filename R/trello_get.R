#' Get Data From Trello API
#'
#' Issues \code{\link[httr]{GET}} requests for Trello API endpoints.
#'
#' It accepts JSON responses and uses \code{\link[jsonlite]{fromJSON}} to convert them into flat \code{data.frame}s. It hrows an error if non-JSON type of data is received. It also takes care of paging (if \code{paging = TRUE}), setting the query parameter \code{before} to the earliest date from the previous result, essentially getting all there is for the given request.
#'
#' For unsuccessfull requests, server error messages are extracted from the response header and reprinted on the console.
#'
#' Functions such as \code{\link{get_board_cards}} or \code{\link{get_card_comments}} are convenience wrappers for this function. They remove the need for specifying the query parameters and optionally simplify the result so as to give you more consistent and easy to work with data.
#' @param url url for the GET request, see \code{\link[httr]{GET}} for details
#' @param query url parameters that form the query, see \code{\link[httr]{GET}} for details
#' @param token previously generated token, see \code{\link{trello_get_token}} for how to obtain it
#' @param paging logical whether paging should be used (if not, results will be limited to 1000 rows)
#' @seealso \code{\link[httr]{GET}}, \code{\link[jsonlite]{fromJSON}}, \code{\link{trello_get_token}}
#' @importFrom dplyr bind_rows
#' @export
#' @examples
#' # For accessing public boards you don't need authorization; this example uses
#' # the publicly available Trello Development Roadmap board (notice the .json
#' # suffix):
#' url = "https://trello.com/b/nC8QJJoZ/trello-development-roadmap.json"
#' tdb = trello_get(url)
#'
#' # This gives you some useful content already, but you may want to do more
#' # specific queries. Let's start by getting the ID of the board:
#' bid = tdb$id
#'
#' # We can now use this id to make specific queries using dedicated functions:
#'
#' tdb_lists = get_board_lists(bid)   # Get lists
#' tdb_labels = get_board_labels(bid) # Get labels
#' tdb_cards = get_board_cards(bid)   # Get cards
#'
#' # Having acquired the card-related data, we can now make queries about specific
#' # cards. As before, we start by getting the ID of the first card:
#' card1_id = tdb_cards$id[1]
#' card1_comm = get_card_comments(card1_id) # Get comments from the card
#'
#' # To retrieve large results, a paging might be necessary:
#'
#' \dontrun{
#' tdb_actions = get_board_actions(bid, filter = "commentCard", paging = TRUE)
#' }
#'
#' # For private boards, you need a secure token to communicate with Trello API
#'
#' \dontrun{
#' token = get_token("your_key", "your_secret")
#'
#' # Get all cards that are not archived
#' all_open = get_request(url, token, query)
#' }

trello_get = function(url,
                      token = NULL,
                      query = NULL,
                      paging = FALSE) {

    cat("Sending request...\n")

    # In case of large results, server only returns 50; change to 1000 instead
    if (is.null(query))       query = list()
    if (is.null(query$limit)) query$limit = "1000"

    if (paging) {

        # Create placeholder for results
        flat = data.frame()

        repeat {

            # Get a batch of data and append to the previous results
            batch = get_flat(url = url, token = token, query = query)
            flat  = tryCatch(
                expr  = bind_rows(flat, batch),
                error = function(e) {
                    message(e)
                    return(list(flat, batch))
                })


            # If paging is needed, set 'before'; otherwise abort
            if (keep_going(batch)) {
                query$before = set_before(batch)
                message("Received 1000 results, keep paging...")
            } else {
                message("Received last page, ", nrow(flat)," results in total")
                break
            }
        }
    } else {

        # Build url and get flattened data
        flat = get_flat(url = url, token = token, query = query)

        # Show out
        if (!is.data.frame(flat)) {
            message("Returning ", class(flat))
        } else if (is.data.frame(flat) & nrow(flat) >= 1000) {
            message("Reached 1000 results; use 'paging = TRUE' to get more")
        } else {
            message("Received ", nrow(flat), " results")
        }
    }
    return(flat)
}

set_before = function(batch) {
    # Get ID that corresponds with the earliest date
    before = batch$id[batch$date == min(batch$date)]
    return(before)
}

keep_going = function(flat) {

    # Only data.frames can be bound by bind_rows; if it isn't one, abort paging
    if (!is.data.frame(flat)) {
        message("Response format is not suitable for paging - finished.")
        go_on = FALSE
    } else go_on = TRUE

    # If the result is shorter than 1000, it is the last page; abort paging
    if (nrow(flat) < 1000) go_on = FALSE

    # My heart must
    return(go_on)
}

#' GET url and return data.frame
#'
#' GET url and return data.frame
#' @param url url to get
#' @param token a secure token
#' @param query additional url parameters (defaults to NULL)
#' @importFrom httr GET content config http_status headers http_type http_error user_agent
#' @importFrom jsonlite fromJSON

get_flat = function(url, token, query = NULL) {

    # Issue request
    req  = GET(url, config(token = token), query = query,
               user_agent("https://github.com/jchrom/trellor"))

    # Print out the complete url
    cat("Request URL:\n", req$url, "\n", sep = "")

    # Handle errors
    if (http_error(req)) stop(http_status(req)$message, " : ", req)

    # Handle response (only JSON is accepted)
    if (http_type(req) == "application/json") {
        json = content(req, as = "text")
        flat = fromJSON(json, flatten = T)
    } else {
        req_trim = paste0(strtrim(content(req, as = "text"), 50), "...")
        stop(http_type(req), " is not JSON : ", req_trim)
    }

    # If the result is an empty list, convert into an empty data.frame
    if (length(flat) == 0) {
        flat = data.frame()
        message("The response is empty")
    }

    # Return the result
    return(flat)
}

