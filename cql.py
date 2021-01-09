#!/usr/bin/python3
import sshtunnel
import time
import argparse

from cassandra import ConsistencyLevel
from cassandra.cluster import Cluster, BatchStatement
from cassandra.query import SimpleStatement
from cassandra.auth import PlainTextAuthProvider

class CassandraClient():
    def __init__(self, cluster_ips, port=9042, user=None, password=None):
        self.user = user
        self.password = password
        self.port = port
        self.credential = PlainTextAuthProvider(username=self.user, password=self.password)
        self.cluster = Cluster(cluster_ips, port=self.port, auth_provider=self.credential)
        self.session = None
    def create_session(self, keyspace=None):
        if not self.session:
            self.session = self.cluster.connect(keyspace)

    def exec(self, query, size=None, paging_state=None):
        statement = SimpleStatement(query, fetch_size=size)
        rows = self.session.execute(statement, paging_state=paging_state)
        return rows

    def exec_async(self, query):
        result = self.session.execute_async()
        return result

class Remote():
    def __init__(self, host, user, password):
        self.host = host
        self.user = user
        self.passwd = password
        self.tunnel = None

    def connect(self, service_host, port):
        self.tunnel = sshtunnel.open_tunnel(
            self.host, ssh_username=self.user, ssh_password=self.passwd,
            remote_bind_address=(service_host, port),
            set_keepalive=0.5,
            #debug_level='TRACE'
            )
        return self.tunnel

    def start(self):
        self.tunnel.start()

    def stop(self):
        self.tunnel.stop()

    def local_port(self):
        return self.tunnel.local_bind_port

    def cmd(self, cmd_str):
        stdin, stdout, stderr = ssh.exec_command(cmd_str)
        return stdout.read().decode()

class Query():
    def __init__(self, cass_ips, port, user, password):
        self.cass_ips = cass_ips.split(',')
        self.port = int(port)
        self.user = user
        self.password = password
        self.size = 50
        self.cql = None
        self.ssh = None
        self.paging_state = None
        self.db = None

    def open(self, host, user, password):
        self.ssh = Remote(host, user, password)
        self.ssh.connect(self.cass_ips[0], self.port)
        self.ssh.start()
        self.port = self.ssh.local_port()
        self.cass_ips = ['127.0.0.1']

    def close(self):
        self.ssh.stop()

    def query(self, cql):
        self.cql = cql
        if not self.db:
            self.db = CassandraClient(self.cass_ips, self.port, self.user, self.password)
        self.db.create_session()
        tm = time.time()
        rows = self.db.exec(cql, size=self.size)
        self.paging_state = rows.paging_state
        return rows.current_rows, time.time() - tm, self.paging_state

    def query_next(self):
        if self.paging_state is None:
            return None, 0, None

        tm = time.time()
        rows = self.db.exec(self.cql, size=self.size, paging_state=self.paging_state)
        self.paging_state = rows.paging_state
        return rows.current_rows, time.time() - tm, self.paging_state

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-r', '--remote-host', help='SSH to remote host')
    parser.add_argument('-u', '--remote-user', help='SSH user')
    parser.add_argument('-p', '--remote-password', help='SSH Password')

    parser.add_argument('--ip', required=True, help='Cassandra Listen IP')
    parser.add_argument('--port', help='Cassandra Listen Port')
    parser.add_argument('--user', help='Cassandra User ')
    parser.add_argument('--passwd', help='Cassandra Password')
    parser.add_argument('--cql', help='Cassandra Query String')
    parser.add_argument('--keyspaces', action='store_true', help='List Cassandra keyspaces')
    parser.add_argument('--tables', action='store_true', help='List All Cassandra keyspaces and tables')

    args = parser.parse_args()

    cass_user = args.user
    cass_passwd = args.passwd
    if not args.user and not args.passwd:
        cass_user = 'sdn'
        cass_passwd = 'sdncassandra'
    port = 9042
    if args.port:
        port = args.port
    q = Query(args.ip, port, cass_user, cass_passwd)

    if args.remote_host:
        password = args.remote_password
        if not password:
            password = input('Password: ')
        user = 'root'
        if args.remote_user:
            user = args.remote_user
        q.open(args.remote_host, user, password)

    cql = args.cql
    if args.keyspaces:
        cql = 'SELECT * FROM system_schema.keyspaces'
    if args.tables:
        cql = 'SELECT keyspace_name, table_name FROM system_schema.tables'

    if cql:
        tm_total = 0
        try:
            rows, tm, page = q.query(cql)
            tm_total += tm
            while rows:
                num = 0
                for row in rows:
                    num +=1
                    print(num, row)
                if not page:
                    break
                input('----more----')
                rows, tm, page = q.query_next()
                tm_total += tm
        except KeyboardInterrupt as e:
            pass
        print('\nTotal Time:', tm_total)
    q.close()

if __name__ == '__main__':
    main()

def test(port=9042):
    #cass = CassandraClient(['172.118.23.20'], port=port, user='sdn', password='sdncassandra')
    cass = CassandraClient(['127.0.0.1'], port=port, user='sdn', password='sdncassandra')
    cass.create_session()
    size = 10
    #rows = cass.select('select * from "ContrailAnalyticsCql".statstablev4')
    tm = time.time()
    #query_str = 'SELECT * FROM "ContrailAnalyticsCql".sessionTable WHERE key=191906826 AND key2=1 AND key3=1 AND key4=0 AND (column1) >= (0) AND (column1, column2, column3) <= (65535, 65535, 2147483647) LIMIT 100000000'
    query_str = 'select * from "ContrailAnalyticsCql".sessiontable'
    rows = cass.exec(query_str, size=size)
    print('execute time:', time.time() - tm)
    #import pdb;pdb.set_trace()
    while True:
        print(rows.paging_state)
        num = 0
        for row in rows.current_rows:
            num +=1
            print(num, row)
        #for row in rows:
        #    print(row)
        if rows.paging_state is None:
            break;
        input('----more----')
        rows = cass.exec('select * from "ContrailAnalyticsCql".sessiontable', size=size, paging_state=rows.paging_state)
