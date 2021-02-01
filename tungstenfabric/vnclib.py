# wrapper for API client
# please install contrail-api-client with python2
from vnc_api import vnc_api

class Api(vnc_api.VncApi):
    def __init__(self, server):
        self.user = 'ArcherAdmin'
        self.pwd = 'ArcherAdmin@123'
        self.tenant = self.user
        self.port = '8082'
        self.server = server
        self.auth_port = '6000'

        super(Api, self).__init__(username=self.user, password=self.pwd, tenant_name=self.tenant,
                                   api_server_host=self.server, api_server_port=self.port,
                                   auth_host=self.server, auth_port=self.auth_port)