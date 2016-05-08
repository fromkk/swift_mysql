#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif
import CMySQL
import SwiftSQL

public enum MysqlError :ErrorProtocol
{
    case Connection
    case QueryFailed
}

public class MysqlConnection
{
    var host :String = ""
    var user :String = ""
    var password :String = ""
    var port :Int = 3306
    var database :String = ""

    private var _connect :UnsafeMutablePointer<MYSQL>

    public init(host :String, user :String, password :String, port :Int, database :String)
    {
        self.host = host
        self.user = user
        self.password = password
        self.port = port
        self.database = database

        self._connect = mysql_init(nil)
    }

    private func _userInfo() -> String
    {
        var result :String = self.user
        if 0 < self.password.characters.count
        {
            result += ":\(self.password)"
        }
        return result + "@"
    }

    public func connection() -> UnsafeMutablePointer<MYSQL> {
        return self._connect
    }

    public func open() throws {
        guard mysql_real_connect(self._connect, self.host, self.user, self.password, self.database, UInt32(self.port), nil, 0) != nil else
        {
            throw MysqlError.Connection
        }
    }

    public func close() -> Void {
        mysql_close(self._connect)
    }

    public func execute(sql :String) throws -> MysqlResult?
    {
        guard mysql_real_query(self._connect, sql, UInt(sql.utf8.count)) == 0 else
        {
            throw MysqlError.QueryFailed
        }

        guard let result :UnsafeMutablePointer<MYSQL_RES> = mysql_store_result(self._connect) else
        {
            return nil
        }

        return MysqlResult(result)
    }
}

public class MysqlResult
{
    public typealias MysqlRow = [String:String]

    public let resultPointer :UnsafeMutablePointer<MYSQL_RES>
    public init(_ resultPointer :UnsafeMutablePointer<MYSQL_RES>)
    {
        self.resultPointer = resultPointer
    }

    public func clear()
    {
        mysql_free_result(self.resultPointer)
    }

    public var count :Int
    {
        return Int(mysql_num_rows(self.resultPointer))
    }

    public lazy var fields :[MysqlField] = {
        var result :[MysqlField] = []
        for i in 0..<mysql_num_fields(self.resultPointer)
        {
            result.append(MysqlField(mysql_fetch_field_direct(self.resultPointer, i)))
        }
        return result
    }()

    public lazy var rows :[MysqlRow] = {
        var result :[MysqlRow] = []
        for i in 0..<self.count
        {
            if let row = self.row(i)
            {
                result.append(row)
            }
        }
        return result
    }()

    public func row(_ index :Int) -> MysqlRow?
    {
        if index > self.count
        {
            return nil
        }

        mysql_data_seek(self.resultPointer, UInt64(index))
        let values :MYSQL_ROW = mysql_fetch_row(self.resultPointer)
        var row :MysqlRow = [:]
        for index in self.fields.indices
        {
            let field :MysqlField = self.fields[index]
            guard let val = values[index] else
            {
                continue
            }

            if let name :String = field.name, let val :String = String(validatingUTF8 :val)
            {
                row[name] = val
            }
        }
        return row
    }

    deinit
    {
        clear()
    }
}

public struct MysqlField
{
    public var name :String?
    public var originalName :String?
    public var table :String?
    public var originalTable :String?
    public var database :String?
    public var catalog :String?
    public var length :Int
    public var maxLength :Int
    public init(_ pointer :UnsafePointer<MYSQL_FIELD>)
    {
        self.name = String(validatingUTF8 :pointer.pointee.name)
        self.originalName = String(validatingUTF8 :pointer.pointee.org_name)
        self.table = String(validatingUTF8 :pointer.pointee.table)
        self.originalTable = String(validatingUTF8 :pointer.pointee.org_table)
        self.database = String(validatingUTF8: pointer.pointee.db)
        self.catalog = String(validatingUTF8: pointer.pointee.catalog)
        self.length = Int(pointer.pointee.length)
        self.maxLength = Int(pointer.pointee.max_length)
    }
}

public class MysqlSelectQueryBulder :SQLSelectQueryBuilder
{
    public var _table :String
    public var _columns :[String] = []
    public var _where :[SQLQueryWhere] = []
    public var _groupBy :[String] = []
    public var _limit :Int?
    public var _offset :Int = 0

    public required init(table :String, columns :[String] = [])
    {
        self._table = table
        self._columns = columns
    }
    internal func limitQuery() -> String
    {
        guard let limit = self._limit else
        {
            return ""
        }

        return " LIMIT \(self._offset), \(limit)"
    }
    public func escape(string :String) -> String
    {
        return self.generalEscape(string :string)
    }
}
