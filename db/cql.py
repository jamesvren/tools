#!/usr/bin/python3
import sshtunnel
import time
import argparse

from cassandra import ConsistencyLevel, DriverException
from cassandra.cluster import Cluster, BatchStatement
from cassandra.query import SimpleStatement, dict_factory
from cassandra.auth import PlainTextAuthProvider

trace = False
def DEBUG(*msg):
    if trace:
        print(*msg)

class CassandraClient():
    def __init__(self, cluster_ips, port=9042, user=None, password=None):
        DEBUG('Create Cluster:', cluster_ips, port, user, password)
        self.user = user
        self.password = password
        self.port = port
        self.ips = cluster_ips
        self.credential = PlainTextAuthProvider(username=self.user, password=self.password)
        self.cluster = Cluster(self.ips, port=self.port, auth_provider=self.credential)
        self.session = None

    def create_session(self, keyspace=None):
        if not self.session:
            try:
                self.session = self.cluster.connect(keyspace)
                self.session.row_factory = dict_factory
            except DriverException as e:
                DEBUG('Failed to connect Cluster:', e)
                if 'Cluster is already shut down' in e:
                    self.cluster = Cluster(self.ips, port=self.port, auth_provider=self.credential)
                    self.create_session(keyspace)

    def exec(self, query, size=None, paging_state=None):
        DEBUG('Send query:', query, size, paging_state)
        statement = SimpleStatement(query, fetch_size=size)
        rows = self.session.execute(statement, paging_state=paging_state)
        DEBUG('Response paging:', rows.paging_state)
        return rows

    def exec_async(self, query):
        result = self.session.execute_async(query)
        return result

class Remote():
    def __init__(self, host, user, password):
        self.host = host
        self.user = user
        self.passwd = password
        self.tunnel = None

    def connect(self, service_host, port):
        DEBUG('Create ssh tunnel:', self.user, self.passwd, self.host, 'bind:', service_host, port)
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
    def __init__(self, cass_ips, port, user, password, debug=False):
        self.cass_ips = cass_ips.split(',')
        self.port = int(port)
        self.user = user
        self.password = password
        self.size = 50
        self.cql = None
        self.ssh = None
        self.paging_state = None
        self.db = None
        if debug:
            global trace
            trace = True

    def open(self, host, user, password):
        self.ssh = Remote(host, user, password)
        self.ssh.connect(self.cass_ips[0], self.port)
        self.ssh.start()
        self.port = self.ssh.local_port()
        self.cass_ips = ['127.0.0.1']

    def close(self):
        if ssh:
            self.ssh.stop()

    def query(self, cql, paging=None):
        self.cql = cql
        if not self.db:
            self.db = CassandraClient(self.cass_ips, self.port, self.user, self.password)
        self.db.create_session()
        tm = time.time()
        rows = self.db.exec(cql, size=self.size, paging_state=paging)
        return rows.current_rows, time.time() - tm, rows.paging_state

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
    parser.add_argument('-c', '--continues', action='store_true', help='Display all result without prompt')
    parser.add_argument('--debug', action='store_true', help='Print debug message')

    args = parser.parse_args()

    cass_user = args.user
    cass_passwd = args.passwd
    if not args.user and not args.passwd:
        cass_user = 'sdn'
        cass_passwd = 'sdncassandra'
    port = 9042
    if args.port:
        port = args.port
    q = Query(args.ip, port, cass_user, cass_passwd, args.debug)

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
                if not args.continues:
                    input('----more----')
                rows, tm, page = q.query_next(cql, page)
                tm_total += tm
        except KeyboardInterrupt as e:
            pass
        print('\nTotal Time:', tm_total)
    q.close()

if __name__ == '__main__':
    main()