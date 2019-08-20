//
//  CICOORMDBService.swift
//  CICOPersistent
//
//  Created by lucky.li on 2018/6/22.
//  Copyright © 2018 cico. All rights reserved.
//
// TODO: refactor for swift lint;
// swiftlint:disable type_body_length
// swiftlint:disable file_length
// swiftlint:disable function_body_length
// swiftlint:disable function_parameter_count

import Foundation
import FMDB
import CICOAutoCodable

public let kCICOORMDBDefaultPassword = "cico_orm_db_default_password"

private let kORMTableName = "cico_orm_table_info"
private let kTableNameColumnName = "table_name"
private let kObjectTypeNameColumnName = "object_type_name"
private let kObjectTypeVersionColumnName = "object_type_version"

///
/// ORM database service;
///
/// You can save any object that conform to codable protocol and ORMProtocol;
///
open class ORMDBService {
    public let fileURL: URL

    private let dbPasswordKey: String?
    private var dbQueue: FMDatabaseQueue?

    deinit {
        print("\(self) deinit")
        self.dbQueue?.close()
    }

    /// Init with database file URL and database encryption password;
    ///
    /// - parameter fileURL: Database file URL;
    /// - parameter password: Database encryption password; It will use default password if not passing this parameter;
    ///             Database won't be encrypted when password is nil;
    ///
    /// - returns: Init object;
    public init(fileURL: URL, password: String? = kCICOORMDBDefaultPassword) {
        self.fileURL = fileURL
        if let password = password {
            self.dbPasswordKey = CICOSecurityAide.md5HashString(with: password)
        } else {
            self.dbPasswordKey = nil
        }
        self.initDB()
    }

    /*******************
     * PUBLIC FUNCTIONS
     *******************/

    /// Read object from database using primary key;
    ///
    /// - parameter objectType: Type of the object, it must conform to codable protocol and ORMProtocol;
    /// - parameter primaryKeyValue: Primary key value of the object in database, it must conform to codable protocol;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    ///
    /// - returns: Read object, nil when no object for this primary key;
    open func readObject<T: CICOORMCodableProtocol>(ofType objectType: T.Type,
                                                    primaryKeyValue: Codable,
                                                    customTableName: String? = nil) -> T? {
        let tableName = self.tableName(objectType: objectType, customTableName: customTableName)
        let primaryKeyColumnName = T.cicoORMPrimaryKeyColumnName()

        return self.pReadObject(ofType: objectType,
                                tableName: tableName,
                                primaryKeyColumnName: primaryKeyColumnName,
                                primaryKeyValue: primaryKeyValue)
    }

    /// Read object array from database using SQL;
    ///
    /// SQL: SELECT * FROM "TableName" WHERE "whereString" ORDER BY "orderByName" DESC/ASC LIMIT "limit";
    ///
    /// - parameter objectType: Type of the object, it must conform to codable protocol and ORMProtocol;
    /// - parameter whereString: Where string for SQL;
    /// - parameter orderByName: Order by name for SQL;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    ///
    /// - returns: Read object, nil when no object for this primary key;
    open func readObjectArray<T: CICOORMCodableProtocol>(ofType objectType: T.Type,
                                                         whereString: String? = nil,
                                                         orderByName: String? = nil,
                                                         descending: Bool = true,
                                                         limit: Int? = nil,
                                                         customTableName: String? = nil) -> [T]? {
        let tableName = self.tableName(objectType: objectType, customTableName: customTableName)

        return self.pReadObjectArray(ofType: objectType,
                                     tableName: tableName,
                                     whereString: whereString,
                                     orderByName: orderByName,
                                     descending: descending,
                                     limit: limit)
    }

    /// Write object into database using primary key;
    ///
    /// Add when it does not exist, update when it exists;
    ///
    /// - parameter object: The object will be saved in database, it must conform to codable protocol and ORMProtocol;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    ///
    /// - returns: Write result;
    open func writeObject<T: CICOORMCodableProtocol>(_ object: T, customTableName: String? = nil) -> Bool {
        let tableName = self.tableName(objectType: T.self, customTableName: customTableName)
        let primaryKeyColumnName = T.cicoORMPrimaryKeyColumnName()
        let indexColumnNameArray = T.cicoORMIndexColumnNameArray()
        let objectTypeVersion = T.cicoORMObjectTypeVersion()

        return self.pWriteObject(object,
                                 tableName: tableName,
                                 primaryKeyColumnName: primaryKeyColumnName,
                                 indexColumnNameArray: indexColumnNameArray,
                                 objectTypeVersion: objectTypeVersion)
    }

    /// Write object array into database using primary key in one transaction;
    ///
    /// Add when it does not exist, update when it exists;
    ///
    /// - parameter objectArray: The object array will be saved in database,
    ///             it must conform to codable protocol and ORMProtocol;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    ///
    /// - returns: Write result;
    open func writeObjectArray<T: CICOORMCodableProtocol>(_ objectArray: [T], customTableName: String? = nil) -> Bool {
        let tableName = self.tableName(objectType: T.self, customTableName: customTableName)
        let primaryKeyColumnName = T.cicoORMPrimaryKeyColumnName()
        let indexColumnNameArray = T.cicoORMIndexColumnNameArray()
        let objectTypeVersion = T.cicoORMObjectTypeVersion()

        return self.pWriteObjectArray(objectArray,
                                      tableName: tableName,
                                      primaryKeyColumnName: primaryKeyColumnName,
                                      indexColumnNameArray: indexColumnNameArray,
                                      objectTypeVersion: objectTypeVersion)
    }

    /// Update object in database using primary key;
    ///
    /// Read the existing object, then call the "updateClosure", and write the object returned by "updateClosure";
    /// It won't update when "updateClosure" returns nil;
    ///
    /// - parameter objectType: Type of the object, it must conform to codable protocol;
    /// - parameter primaryKeyValue: Primary key value of the object in database, it must conform to codable protocol;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    /// - parameter updateClosure: It will be called after reading object from database,
    ///             the read object will be passed as parameter, you can return a new value to update in database;
    ///             It won't be updated to database when you return nil by this closure;
    /// - parameter completionClosure: It will be called when completed, passing update result as parameter;
    open func updateObject<T: CICOORMCodableProtocol>(ofType objectType: T.Type,
                                                      primaryKeyValue: Codable,
                                                      customTableName: String? = nil,
                                                      updateClosure: (T?) -> T?,
                                                      completionClosure: ((Bool) -> Void)? = nil) {
        let tableName = self.tableName(objectType: objectType, customTableName: customTableName)
        let primaryKeyColumnName = T.cicoORMPrimaryKeyColumnName()
        let indexColumnNameArray = T.cicoORMIndexColumnNameArray()
        let objectTypeVersion = T.cicoORMObjectTypeVersion()

        self.pUpdateObject(ofType: objectType,
                           tableName: tableName,
                           primaryKeyColumnName: primaryKeyColumnName,
                           primaryKeyValue: primaryKeyValue,
                           indexColumnNameArray: indexColumnNameArray,
                           objectTypeVersion: objectTypeVersion,
                           updateClosure: updateClosure,
                           completionClosure: completionClosure)
    }

    /// Remove object from database using primary key;
    ///
    /// - parameter objectType: Type of the object, it must conform to codable protocol;
    /// - parameter primaryKeyValue: Primary key value of the object in database, it must conform to codable protocol;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    ///
    /// - returns: Remove result;
    open func removeObject<T: CICOORMCodableProtocol>(ofType objectType: T.Type,
                                                      primaryKeyValue: Codable,
                                                      customTableName: String? = nil) -> Bool {
        let tableName = self.tableName(objectType: objectType, customTableName: customTableName)
        let primaryKeyColumnName = T.cicoORMPrimaryKeyColumnName()

        return self.pRemoveObject(ofType: objectType,
                                  tableName: tableName,
                                  primaryKeyColumnName: primaryKeyColumnName,
                                  primaryKeyValue: primaryKeyValue)
    }

    /// Remove the whole table from database by table name;
    ///
    /// - parameter objectType: Type of the object, it must conform to codable protocol;
    /// - parameter customTableName: One class or struct can be saved in different tables,
    ///             you can define your custom table name here;
    ///             It will use default table name according to the class or struct name when passing nil;
    ///
    /// - returns: Remove result;
    open func removeObjectTable<T: CICOORMCodableProtocol>(ofType objectType: T.Type,
                                                           customTableName: String? = nil) -> Bool {
        let tableName = self.tableName(objectType: objectType, customTableName: customTableName)

        return self.pRemoveObjectTable(ofType: objectType, tableName: tableName)
    }

    /// Remove all tables from database;
    ///
    /// - returns: Remove result;
    open func clearAll() -> Bool {
        self.dbQueue = nil
        let result = CICOFileManagerAide.removeFile(with: self.fileURL)
        self.dbQueue = FMDatabaseQueue.init(url: self.fileURL)
        return result
    }

    /********************
     * PRIVATE FUNCTIONS
     ********************/

    ///
    private func pReadObject<T: Codable>(ofType objectType: T.Type,
                                         tableName: String,
                                         primaryKeyColumnName: String,
                                         primaryKeyValue: Codable) -> T? {
        var object: T?

        let objectTypeName = "\(objectType)"

        self.dbQueue?.inTransaction({ (database, _) in
            guard self.isTableExist(database: database, objectTypeName: objectTypeName, tableName: tableName) else {
                return
            }

            object = self.readObject(database: database,
                                     objectType: objectType,
                                     tableName: tableName,
                                     primaryKeyColumnName: primaryKeyColumnName,
                                     primaryKeyValue: primaryKeyValue)
        })

        return object
    }

    private func pReadObjectArray<T: Codable>(ofType objectType: T.Type,
                                              tableName: String,
                                              whereString: String? = nil,
                                              orderByName: String? = nil,
                                              descending: Bool = true,
                                              limit: Int? = nil) -> [T]? {
        var array: [T]?

        let objectTypeName = "\(objectType)"

        self.dbQueue?.inTransaction({ (database, _) in
            guard self.isTableExist(database: database, objectTypeName: objectTypeName, tableName: tableName) else {
                return
            }

            array = self.readObjectArray(database: database,
                                         objectType: objectType,
                                         tableName: tableName,
                                         whereString: whereString,
                                         orderByName: orderByName,
                                         descending: descending,
                                         limit: limit)
        })

        return array
    }

    private func pWriteObject<T: Codable>(_ object: T,
                                          tableName: String,
                                          primaryKeyColumnName: String,
                                          indexColumnNameArray: [String]?,
                                          objectTypeVersion: Int) -> Bool {
        var result = false

        let objectType = T.self

        self.dbQueue?.inTransaction({ (database, rollback) in
            // create table if not exist and upgrade table if needed
            let isTableReady =
                self.fixTableIfNeeded(database: database,
                                      objectType: objectType,
                                      tableName: tableName,
                                      primaryKeyColumnName: primaryKeyColumnName,
                                      indexColumnNameArray: indexColumnNameArray,
                                      objectTypeVersion: objectTypeVersion)

            if !isTableReady {
                rollback.pointee = true
                return
            }

            // replace table record
            result = self.replaceRecord(database: database, tableName: tableName, object: object)
            if !result {
                rollback.pointee = true
                return
            }
        })

        return result
    }

    private func pWriteObjectArray<T: Codable>(_ objectArray: [T],
                                               tableName: String,
                                               primaryKeyColumnName: String,
                                               indexColumnNameArray: [String]?,
                                               objectTypeVersion: Int) -> Bool {
        var result = false

        let objectType = T.self

        self.dbQueue?.inTransaction({ (database, rollback) in
            // create table if not exist and upgrade table if needed
            let isTableReady =
                self.fixTableIfNeeded(database: database,
                                      objectType: objectType,
                                      tableName: tableName,
                                      primaryKeyColumnName: primaryKeyColumnName,
                                      indexColumnNameArray: indexColumnNameArray,
                                      objectTypeVersion: objectTypeVersion)

            if !isTableReady {
                rollback.pointee = true
                return
            }

            for object in objectArray {
                // replace table record
                result = self.replaceRecord(database: database, tableName: tableName, object: object)
                if !result {
                    rollback.pointee = true
                    return
                }
            }
        })

        return result
    }

    private func pUpdateObject<T: Codable>(ofType objectType: T.Type,
                                           tableName: String,
                                           primaryKeyColumnName: String,
                                           primaryKeyValue: Codable,
                                           indexColumnNameArray: [String]?,
                                           objectTypeVersion: Int,
                                           updateClosure: (T?) -> T?,
                                           completionClosure: ((Bool) -> Void)?) {
        var result = false
        defer {
            completionClosure?(result)
        }

        let objectTypeName = "\(objectType)"

        self.dbQueue?.inTransaction({ (database, rollback) in
            var object: T?

            let tableExist = self.isTableExist(database: database, objectTypeName: objectTypeName, tableName: tableName)
            if tableExist {
                object = self.readObject(database: database,
                                         objectType: objectType,
                                         tableName: tableName,
                                         primaryKeyColumnName: primaryKeyColumnName,
                                         primaryKeyValue: primaryKeyValue)
            }

            guard let newObject = updateClosure(object) else {
                result = true
                return
            }

            // create table if not exist and upgrade table if needed
            let isTableReady =
                self.fixTableIfNeeded(database: database,
                                      objectType: objectType,
                                      tableName: tableName,
                                      primaryKeyColumnName: primaryKeyColumnName,
                                      indexColumnNameArray: indexColumnNameArray,
                                      objectTypeVersion: objectTypeVersion)

            if !isTableReady {
                rollback.pointee = true
                return
            }

            result = self.replaceRecord(database: database, tableName: tableName, object: newObject)
            if !result {
                rollback.pointee = true
            }
        })
    }

    private func pRemoveObject<T: Codable>(ofType objectType: T.Type,
                                           tableName: String,
                                           primaryKeyColumnName: String,
                                           primaryKeyValue: Codable) -> Bool {
        var result = false

        let objectTypeName = "\(objectType)"

        self.dbQueue?.inTransaction({ (database, rollback) in
            guard self.isTableExist(database: database, objectTypeName: objectTypeName, tableName: tableName) else {
                result = true
                return
            }

            result = self.deleteRecord(database: database,
                                       tableName: tableName,
                                       primaryKeyColumnName: primaryKeyColumnName,
                                       primaryKeyValue: primaryKeyValue)
            if !result {
                rollback.pointee = true
                return
            }
        })

        return result
    }

    private func pRemoveObjectTable<T: Codable>(ofType objectType: T.Type, tableName: String) -> Bool {
        var result = false

        let objectTypeName = "\(objectType)"

        self.dbQueue?.inTransaction({ (database, rollback) in
            guard self.isTableExist(database: database, objectTypeName: objectTypeName, tableName: tableName) else {
                result = true
                return
            }

            result = self.dropTable(database: database, tableName: tableName)
            if !result {
                rollback.pointee = true
                return
            }

            result = self.deleteRecord(database: database,
                                       tableName: kORMTableName,
                                       primaryKeyColumnName: kTableNameColumnName,
                                       primaryKeyValue: tableName)
            if !result {
                rollback.pointee = true
                return
            }
        })

        return result
    }

    private func initDB() {
        let dirURL = self.fileURL.deletingLastPathComponent()
        let result = CICOFileManagerAide.createDir(with: dirURL)
        if !result {
            print("[ERROR]: create database dir failed")
            return
        }

        guard let dbQueue = FMDatabaseQueue.init(url: self.fileURL) else {
            print("[ERROR]: create database failed")
            return
        }

        dbQueue.inDatabase { (database) in
            if let key = self.dbPasswordKey {
                database.setKey(key)
            }

            let result = self.createORMTableInfoTableIfNotExists(database: database)
            if result {
                self.dbQueue = dbQueue
            }
        }
    }

    private func tableName<T>(objectType: T.Type, customTableName: String? = nil) -> String {
        let tableName: String
        if let customTableName = customTableName {
            tableName = customTableName
        } else {
            tableName = "table_\(objectType)"
        }
        return tableName
    }

    private func indexName(indexColumnName: String, tableName: String) -> String {
        return "index_\(indexColumnName)_of_\(tableName)"
    }

    private func createORMTableInfoTableIfNotExists(database: FMDatabase) -> Bool {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(kORMTableName) (\(kTableNameColumnName) TEXT NOT NULL,
        \(kObjectTypeNameColumnName) TEXT NOT NULL,
        \(kObjectTypeVersionColumnName) INTEGER NOT NULL,
        PRIMARY KEY(\(kTableNameColumnName)));
        """

         //        print("[SQL]: \(createTableSQL)")
        let result = database.executeUpdate(createTableSQL, withArgumentsIn: [])
        if !result {
            print("[ERROR]: SQL = \(createTableSQL)")
        }

        return result
    }

    private func readORMTableInfo(database: FMDatabase,
                                  objectTypeName: String,
                                  tableName: String) -> ORMTableInfoModel? {
        var tableInfo: ORMTableInfoModel?

        let querySQL = "SELECT * FROM \(kORMTableName) WHERE \(kTableNameColumnName) = ? LIMIT 1;"

        //        print("[SQL]: \(querySQL)")
        guard let resultSet = database.executeQuery(querySQL, withArgumentsIn: [tableName]) else {
            return tableInfo
        }

        if resultSet.next() {
            if let objectTypeNameValue = resultSet.string(forColumn: kObjectTypeNameColumnName),
                objectTypeNameValue == objectTypeName {
                let objectTypeVersion: Int = resultSet.long(forColumn: kObjectTypeVersionColumnName)
                let temp = ORMTableInfoModel.init(tableName: tableName,
                                                      objectTypeName: objectTypeNameValue,
                                                      objectTypeVersion: objectTypeVersion)
                tableInfo = temp
            }
        }

        resultSet.close()

        return tableInfo
    }

    private func writeORMTableInfo(database: FMDatabase, tableInfo: ORMTableInfoModel) -> Bool {
        var result = false

        let replaceSQL = """
        REPLACE INTO \(kORMTableName) (\(kTableNameColumnName),
        \(kObjectTypeNameColumnName),
        \(kObjectTypeVersionColumnName)) VALUES (?, ?, ?);
        """
        let argumentArray: [Any] = [tableInfo.tableName, tableInfo.objectTypeName, tableInfo.objectTypeVersion]

        //        print("[SQL]: \(replaceSQL)")
        result = database.executeUpdate(replaceSQL, withArgumentsIn: argumentArray)
        if !result {
            print("[ERROR]: SQL = \(replaceSQL)")
        }

        return result
    }

    private func removeORMTableInfo(database: FMDatabase, tableName: String) -> Bool {
        return self.deleteRecord(database: database,
                                 tableName: kORMTableName,
                                 primaryKeyColumnName: kTableNameColumnName,
                                 primaryKeyValue: tableName)
    }

    private func fixTableIfNeeded<T: Codable>(database: FMDatabase,
                                              objectType: T.Type,
                                              tableName: String,
                                              primaryKeyColumnName: String,
                                              indexColumnNameArray: [String]?,
                                              objectTypeVersion: Int) -> Bool {
        var result = false

        let objectTypeName = "\(objectType)"

        guard let tableInfo = self.readORMTableInfo(database: database,
                                                    objectTypeName: objectTypeName,
                                                    tableName: tableName) else {
            result = self.createTableAndIndexs(database: database,
                                               objectType: objectType,
                                               tableName: tableName,
                                               primaryKeyColumnName: primaryKeyColumnName,
                                               indexColumnNameArray: indexColumnNameArray,
                                               objectTypeVersion: objectTypeVersion)
            return result
        }

        guard tableInfo.objectTypeVersion >= objectTypeVersion else {
            // upgrade column
            let columnSet = self.queryTableColumns(database: database, tableName: tableName)
            let sqliteTypeDic = SQLiteTypeDecoder.allTypeProperties(of: objectType)
            let newColumnSet = Set<String>.init(sqliteTypeDic.keys)
            let needAddColumnSet = newColumnSet.subtracting(columnSet)

            for columnName in needAddColumnSet {
                let sqliteType = sqliteTypeDic[columnName]!
                result = self.addColumn(database: database,
                                        tableName: tableName,
                                        columnName: columnName,
                                        columnType: sqliteType.sqliteType.rawValue)
                if !result {
                    return result
                }
            }

            // upgrade indexs
            let indexSet = self.queryTableIndexs(database: database, tableName: tableName)
            let newIndexSet: Set<String>
            let newIndexDic: [String: String]
            if let indexColumnNameArray = indexColumnNameArray {
                var tempSet = Set<String>.init()
                var tempIndexDic = [String: String]()
                indexColumnNameArray.forEach { (indexColumnName) in
                    let indexName = self.indexName(indexColumnName: indexColumnName, tableName: tableName)
                    tempSet.insert(indexName)
                    tempIndexDic[indexName] = indexColumnName
                }
                newIndexSet = tempSet
                newIndexDic = tempIndexDic
            } else {
                newIndexSet = Set<String>.init()
                newIndexDic = [String: String]()
            }

            let needAddIndexSet = newIndexSet.subtracting(indexSet)
            for indexName in needAddIndexSet {
                let indexColumnName = newIndexDic[indexName]!
                result = self.createIndex(database: database,
                                          indexName: indexName,
                                          tableName: tableName,
                                          indexColumnName: indexColumnName)
                if !result {
                    return result
                }
            }

            let needDeleteIndexSet = indexSet.subtracting(newIndexSet)
            for indexName in needDeleteIndexSet {
                result = self.dropIndex(database: database, indexName: indexName)
                if !result {
                    return result
                }
            }

            // update objectTypeVersion
            let newTableInfo = ORMTableInfoModel.init(tableName: tableName,
                                                          objectTypeName: objectTypeName,
                                                          objectTypeVersion: objectTypeVersion)
            result = self.writeORMTableInfo(database: database, tableInfo: newTableInfo)

            return result
        }

        result = true

        return result
    }

    private func isTableExist(database: FMDatabase, objectTypeName: String, tableName: String) -> Bool {
        if self.readORMTableInfo(database: database, objectTypeName: objectTypeName, tableName: tableName) != nil {
            return true
        } else {
            return false
        }
    }

    private func createTableAndIndexs<T: Codable>(database: FMDatabase,
                                                  objectType: T.Type,
                                                  tableName: String,
                                                  primaryKeyColumnName: String,
                                                  indexColumnNameArray: [String]?,
                                                  objectTypeVersion: Int) -> Bool {
        var result = false

        let objectTypeName = "\(objectType)"

        // create table

        let sqliteTypeDic = SQLiteTypeDecoder.allTypeProperties(of: objectType)
        //            print("\nsqliteTypes: \(sqliteTypes)")

        var createTableSQL = "CREATE TABLE IF NOT EXISTS \(tableName) ("
        var isFirst = true
        sqliteTypeDic.forEach({ (name, sqliteType) in
            if isFirst {
                isFirst = false
                createTableSQL.append("\(name)")
            } else {
                createTableSQL.append(", \(name)")
            }

            createTableSQL.append(" \(sqliteType.sqliteType.rawValue)")

            if name == primaryKeyColumnName {
                createTableSQL.append(" NOT NULL")
            }
        })
        createTableSQL.append(", PRIMARY KEY(\(primaryKeyColumnName))")
        createTableSQL.append(");")

        //            print("[SQL]: \(createTableSQL)")
        result = database.executeUpdate(createTableSQL, withArgumentsIn: [])
        if !result {
            print("[ERROR]: SQL = \(createTableSQL)")
            return result
        }

        // create index
        if let indexColumnNameArray = indexColumnNameArray {
            for indexColumnName in indexColumnNameArray {
                let indexName = self.indexName(indexColumnName: indexColumnName, tableName: tableName)
                result = self.createIndex(database: database,
                                          indexName: indexName,
                                          tableName: tableName,
                                          indexColumnName: indexColumnName)
                if !result {
                    return result
                }
            }
        }

        // save table info
        let tableInfo = ORMTableInfoModel.init(tableName: tableName,
                                               objectTypeName: objectTypeName,
                                               objectTypeVersion: objectTypeVersion)
        result = self.writeORMTableInfo(database: database, tableInfo: tableInfo)

        return result
    }

    private func queryTableColumns(database: FMDatabase, tableName: String) -> Set<String> {
        var columnSet = Set<String>.init()

        let querySQL = "PRAGMA TABLE_INFO(\(tableName));"

        guard let resultSet = database.executeQuery(querySQL, withArgumentsIn: []) else {
            return columnSet
        }

        while resultSet.next() {
            if let name = resultSet.string(forColumn: "name") {
                columnSet.insert(name)
            }
        }

        resultSet.close()

        //        print("\(columnSet)")

        return columnSet
    }

    private func queryTableIndexs(database: FMDatabase, tableName: String) -> Set<String> {
        var indexSet = Set<String>.init()

        let querySQL = """
        SELECT name FROM SQLITE_MASTER WHERE type = 'index' AND tbl_name = '\(tableName)' AND sql IS NOT NULL;
        """

        guard let resultSet = database.executeQuery(querySQL, withArgumentsIn: []) else {
            return indexSet
        }

        while resultSet.next() {
            if let name = resultSet.string(forColumn: "name") {
                indexSet.insert(name)
            }
        }

        resultSet.close()

        //        print("\(indexSet)")

        return indexSet
    }

    private func readObject<T: Codable>(database: FMDatabase,
                                        objectType: T.Type,
                                        tableName: String,
                                        primaryKeyColumnName: String,
                                        primaryKeyValue: Codable) -> T? {
        var object: T?

        let querySQL = "SELECT * FROM \(tableName) WHERE \(primaryKeyColumnName) = ? LIMIT 1;"

        //            print("[SQL]: \(querySQL)")
        guard let resultSet = database.executeQuery(querySQL, withArgumentsIn: [primaryKeyValue]) else {
            print("[ERROR]: SQL = \(querySQL)")
            return object
        }

        if resultSet.next() {
            object = SQLiteRecordDecoder.decodeSQLiteRecord(resultSet: resultSet, objectType: objectType)
        }

        resultSet.close()

        return object
    }

    private func readObjectArray<T: Codable>(database: FMDatabase,
                                             objectType: T.Type,
                                             tableName: String,
                                             whereString: String? = nil,
                                             orderByName: String? = nil,
                                             descending: Bool = true,
                                             limit: Int? = nil) -> [T]? {
        var array: [T]?

        let objectTypeName = "\(objectType)"

        var querySQL = "SELECT * FROM \(tableName)"
        var argumentArray = [Any]()

        if let whereString = whereString {
            querySQL.append(" WHERE \(whereString)")
        }

        if let orderByName = orderByName {
            querySQL.append(" ORDER BY \(orderByName)")
            if descending {
                querySQL.append(" DESC")
            } else {
                querySQL.append(" ASC")
            }
        }

        if let limit = limit {
            querySQL.append(" LIMIT ?")
            argumentArray.append(limit)
        }

        querySQL.append(";")

        //            print("[SQL]: \(querySQL)")
        guard let resultSet = database.executeQuery(querySQL, withArgumentsIn: argumentArray) else {
            print("[ERROR]: SQL = \(querySQL)")
            return array
        }

        defer {
            resultSet.close()
        }

        var tempArray = [T]()
        while resultSet.next() {
            guard let object = SQLiteRecordDecoder.decodeSQLiteRecord(resultSet: resultSet,
                                                                      objectType: objectType) else {
                return array
            }
            tempArray.append(object)
        }
        array = tempArray

        return array
    }

    private func replaceRecord<T: Codable>(database: FMDatabase, tableName: String, object: T) -> Bool {
        var result = false

        let (sql, arguments) =
            SQLiteRecordEncoder.encodeObjectToSQL(object: object, tableName: tableName)

        guard let replaceSQL = sql, let argumentArray = arguments else {
            return result
        }

        //        print("[SQL]: \(replaceSQL)")
        result = database.executeUpdate(replaceSQL, withArgumentsIn: argumentArray)
        if !result {
            print("[ERROR]: SQL = \(replaceSQL)")
        }

        return result
    }

    private func deleteRecord(database: FMDatabase,
                              tableName: String,
                              primaryKeyColumnName: String,
                              primaryKeyValue: Codable) -> Bool {
        var result = false

        let deleteSQL = "DELETE FROM \(tableName) WHERE \(primaryKeyColumnName) = ?;"

        //        print("[SQL]: \(deleteSQL)")
        result = database.executeUpdate(deleteSQL, withArgumentsIn: [primaryKeyValue])
        if !result {
            print("[ERROR]: SQL = \(deleteSQL)")
        }

        return result
    }

    private func dropTable(database: FMDatabase, tableName: String) -> Bool {
        var result = false

        let dropSQL = "DROP TABLE \(tableName);"

        //        print("[SQL]: \(dropSQL)")
        result = database.executeUpdate(dropSQL, withArgumentsIn: [])
        if !result {
            print("[ERROR]: SQL = \(dropSQL)")
        }

        return result
    }

    private func addColumn(database: FMDatabase, tableName: String, columnName: String, columnType: String) -> Bool {
        let alterSQL = "ALTER TABLE \(tableName) ADD COLUMN \(columnName) \(columnType);"

        //print("[SQL]: \(alterSQL)")
        let result = database.executeUpdate(alterSQL, withArgumentsIn: [])
        if !result {
            print("[ERROR]: SQL = \(alterSQL)")
        }

        return result
    }

    private func createIndex(database: FMDatabase,
                             indexName: String,
                             tableName: String,
                             indexColumnName: String) -> Bool {
        let createIndexSQL = "CREATE INDEX \(indexName) ON \(tableName)(\(indexColumnName));"

        //print("[SQL]: \(createIndexSQL)")
        let result = database.executeUpdate(createIndexSQL, withArgumentsIn: [])
        if !result {
            print("[ERROR]: SQL = \(createIndexSQL)")
        }

        return result
    }

    private func dropIndex(database: FMDatabase, indexName: String) -> Bool {
        let dropIndexSQL = "DROP INDEX \(indexName);"

        //print("[SQL]: \(dropIndexSQL)")
        let result = database.executeUpdate(dropIndexSQL, withArgumentsIn: [])
        if !result {
            print("[ERROR]: SQL = \(dropIndexSQL)")
        }

        return result
    }
}
