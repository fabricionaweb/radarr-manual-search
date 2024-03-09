#!/bin/bash -e

# -----------------------------------------
# Radarr API key
API_KEY=""
# Radarr API URL
API_URL="http://tower.lan:7878/api/v3"
# Tag to apply and to filter
TAG_LABEL="upgraded"
# Limit to upgrade before stops
LIMIT=4
# -----------------------------------------

# API param
HEADER="x-api-key: ${API_KEY}"

# Get and set the $tagId for the $TAG_LABEL
find_tag_id() {
  tagId=$(curl -sSH "${HEADER}" "${API_URL}/tag" |
    jq --arg tagLabel "${TAG_LABEL}" -c '.[] | select(.label == $tagLabel) | .id')

  # Create tag if not found
  if [[ -z "${tagId}" ]]; then
    tagId=$(curl -sSH "${HEADER}" -X POST "${API_URL}/tag" \
      -H 'content-type: application/json' -d "{\"label\":\"${TAG_LABEL}\"}" | jq -c '.id')

    echo -e "=> Tag '${TAG_LABEL}' created."
  fi

  # Failed to create the tag
  if [[ -z "${tagId}" ]]; then
    echo -e "=> Failed to create '${TAG_LABEL}'."
    exit 1
  fi
}

# Find monitored and available items without $tagId
find_movies() {
  readarray -t monitoredMovies < <(curl -sSH "${HEADER}" "${API_URL}/movie" |
    jq --arg tagId "${tagId}" \
      -c '.[] | select(.monitored == true and .isAvailable == true and (.tags | contains([$tagId | tonumber]) | not)) | {id,title}')

  if [[ ${#monitoredMovies[@]} -eq 0 ]]; then
    echo -e "=> No movies available to upgrade."
    exit 0
  fi

  echo -e "=> Found ${#monitoredMovies[@]} movies to upgrade."
}

# Call Radarr manual search (performs a full search)
ask_search() {
  for movie in "${monitoredMovies[@]}"; do
    movieId="$(jq -r '.id' <<<"${movie}")"
    movieTitle="$(jq -r '.title' <<<"${movie}")"

    printf "=> Asking search for: ${movieTitle}"
    # Call search
    curl -sSH "${HEADER}" -X POST "${API_URL}/command" \
      -H 'content-type: application/json' -d "{\"name\":\"MoviesSearch\",\"movieIds\":[${movieId}]}" \
      -o /dev/null
    # Update tag
    curl -sSH "${HEADER}" -X PUT "${API_URL}/movie/editor" \
      -H 'content-type: application/json' -d "{\"movieIds\":[${movieId}],\"tags\":[${tagId}],\"applyTags\":\"add\"}" \
      -o /dev/null
    printf " ✓\\n"

    if [[ $((--LIMIT)) -eq 0 || ${#monitoredMovies[@]} -eq 1 ]]; then
      echo -e "=> Reached limit. Done."
      exit 0
    fi

    wait_working
  done
}

# Wait 30 seconds to Radarr search work
wait_working() {
  echo -e "=> Waiting 30 seconds before call the next movie:"
  for i in {1..30}; do
    sleep 1
    printf "."
  done
  echo -e ""
}

find_tag_id
find_movies
ask_search
