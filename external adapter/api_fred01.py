import requests
#%%
api_key = '7817752224816662f4f155d53988793f'
series_id = 'MEDCPIM158SFRBCLE'
# fred_url = 'https://api.stlouisfed.org/fred/series/release?file_type=json'
fred_url = 'https://api.stlouisfed.org/fred/series/observations?file_type=json&limit=1&offset=0&sort_order=desc&units=lin'
api_url = fred_url + '&series_id=' + series_id + '&api_key=' + api_key



response = requests.get(api_url)
if response.status_code == requests.codes.ok:
    print(response.text)
else:
    print("Error:", response.status_code, response.text)
# %%

date_url = "https://api.stlouisfed.org/fred/releases/dates?file_type=json&include_release_dates_with_no_data=true"