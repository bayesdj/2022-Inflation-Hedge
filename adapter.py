from bridge import Bridge
# import json

class Adapter:
    # base_url = 'https://min-api.cryptocompare.com/data/price'
    # from_params = ['base', 'from', 'coin']
    # to_params = ['quote', 'to', 'market']

    def __init__(self, inputs):
        self.id = inputs.get('id', '1')
        # self.request_data = input.get('data')
        # self.id = 1
        self.url = 'https://api.stlouisfed.org/fred/series/observations?file_type=json&limit=1&offset=0&sort_order=desc&units=lin&series_id=MEDCPIM158SFRBCLE&api_key=7817752224816662f4f155d53988793f'
        # if self.validate_request_data():
        self.bridge = Bridge()
        # self.set_params()
        self.create_request()
        # else:
        #     self.result_error('No data provided')

    # def validate_request_data(self):
    #     if self.request_data is None:
    #         return False
    #     if self.request_data == {}:
    #         return False
    #     return True

    # def set_params(self):
    #     for param in self.from_params:
    #         self.from_param = self.request_data.get(param)
    #         if self.from_param is not None:
    #             break
    #     for param in self.to_params:
    #         self.to_param = self.request_data.get(param)
    #         if self.to_param is not None:
    #             break

    def create_request(self):
        try:
            params = {}
            response = self.bridge.request(self.url, params)
            
            data = response.json()['observations'][0]
            self.result = data['value']
            data['result'] = self.result
            self.result_success(data)
        except Exception as e:
            self.result_error(e)
        finally:
            self.bridge.close()

    def result_success(self, data):
        self.result = {
            'jobRunID': self.id,
            'data': data,
            'result': self.result,
            'statusCode': 200,
        }

    def result_error(self, error):
        self.result = {
            'jobRunID': self.id,
            'status': 'errored',
            'error': f'There was an error: {error}',
            'statusCode': 500,
        }


# a = Adapter({})
# p = 3