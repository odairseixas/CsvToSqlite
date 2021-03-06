#import "StringProcessor.h"

#import "CsvDefaultValues.h"
#import "CsvToSqlite.h"
#import "CsvToSqlite+Test.h"
#import "CsvColumnsParser.h"
#import "CsvSchemaMismatchError.h"

#include <iterator>

typedef std::vector<std::string> string_vt;

using namespace ::Utils;

static const std::string STL_QUOTE( "'" );

typedef void (^DateStringConverter)( const std::string &date_, std::string& result_ );

static std::string generalConvertToSqlParams(const std::string &sourceString,
                                             DateStringConverter dateConverter_,
                                             CsvDefaultValues* defaultValues_,
                                             NSOrderedSet* csvSchema_,
                                             NSDictionary* schema_,
                                             char separator_);

static string_vt &split(const std::string &s, char delim, string_vt &elems) {
    std::stringstream ss(s);
    std::string item;
    while(std::getline(ss, item, delim)) {
        elems.push_back(item);
    }
    if ( s[ s.size() - 1 ] == delim )
    {
        elems.push_back("");
    }
    return elems;
}

static string_vt split(const std::string &s, char delim) {
    string_vt elems;
    return split(s, delim, elems);
}

@implementation StringProcessor


std::string fastConvertToSqlParams( CsvToSqlite* csvToSqlite_,
                                   const std::string &sourceString,
                                   NSUInteger requeredNumOfColumns_,
                                   NSError** errorPtr_ )
{
    DateStringConverter dateConverter_;
    
    if ( [ @"yyyyMMdd" isEqualToString: csvToSqlite_.csvDateFormat ] )
    {
        dateConverter_ = ^void( const std::string& dateStr_,  std::string& result_ )
        {
            result_.resize( 10, '-' );
            
            result_[0] = dateStr_[0];
            result_[1] = dateStr_[1];
            result_[2] = dateStr_[2];
            result_[3] = dateStr_[3];
            
            
            result_[5] = dateStr_[4];
            result_[6] = dateStr_[5];
            
            result_[8] = dateStr_[6];
            result_[9] = dateStr_[7];
        };
    }
    else if ( [ @"yyyy-MM-dd" isEqualToString: csvToSqlite_.csvDateFormat ] )
    {
        //TODO: @igk date converter not needed!!!
        dateConverter_ = ^void( const std::string& dateStr_,  std::string& result_ )
        {
            result_ = dateStr_;
        };
    }
    else
    {
        dateConverter_ = ^void( const std::string & dateStr_, std::string& result_ )
        {
            NSString* lineStr_ = @( dateStr_.c_str() );
            NSDate* date_ = [ csvToSqlite_.csvFormatter dateFromString: lineStr_ ];
            NSString* resultStr_ = [ csvToSqlite_.ansiFormatter stringFromDate: date_ ];
            
            result_ = [ resultStr_ cStringUsingEncoding: NSUTF8StringEncoding ];
        };
    }
   
    return generalConvertToSqlParams( sourceString,
                                     dateConverter_,
                                     csvToSqlite_.defaultValues,
                                     csvToSqlite_.csvSchema,
                                     csvToSqlite_.schema,
                                     csvToSqlite_.columnsParser->_separator,
                                     requeredNumOfColumns_,
                                     errorPtr_ );
}

static std::string generalConvertToSqlParams(const std::string &sourceString,
                                              DateStringConverter dateConverter_,
                                              CsvDefaultValues* defaultValues_,
                                              NSOrderedSet* csvSchema_,
                                              NSDictionary* schema_,
                                              char separator_,
                                              NSUInteger requeredNumOfColumns_,
                                              NSError** errorPtr_ )
{    
    NSOrderedSet* defaultColumns_ = defaultValues_.columns;
    
    string_vt lineRecords_ = split( sourceString, separator_ );
    
    if ( lineRecords_.size() != requeredNumOfColumns_ )
    {
        *errorPtr_ = [ CsvSchemaMismatchError new ];
        return "";
    }
        
    std::string wrappedLineRecord_;
    string_vt wrappedLine_;
    
    NSUInteger i_        = 0;
    NSString* tmpHeader_ = nil;
    NSString* sqlType_   = nil;
    NSUInteger csvCount_ = [ csvSchema_ count ];
    
    static const size_t TWO_QUOTES_LENGTH = 2;
    
    for ( auto it_ = lineRecords_.begin(); it_ != lineRecords_.end(); ++it_ )
    {
        if ( i_ < csvCount_ )
        {
            tmpHeader_ = [ csvSchema_ objectAtIndex: i_ ];
        }
        else
        {
            tmpHeader_ = [ defaultColumns_ objectAtIndex: i_ - csvCount_ ];
        }
        sqlType_ = [ schema_ objectForKey: tmpHeader_ ];
        
        if ( isSqlDateType( sqlType_ ) )
        {
            dateConverter_( *it_, wrappedLineRecord_ );
        }
        else
        {
            wrappedLineRecord_ = *it_;
        }
        
        char* cStrResultSQL_ = ::sqlite3_mprintf( "%q", wrappedLineRecord_.c_str() );
        ObjcScopedGuard sqlitePrintfGuard_
        (
         ^void(){ ::sqlite3_free( cStrResultSQL_ ); }
         );
        
        {
            // @adk - performance optimization
            
            size_t cStrResultSQLSize_ = ::strlen( cStrResultSQL_ );
            std::string quotedResultSQL_( cStrResultSQLSize_ + TWO_QUOTES_LENGTH, '\'' );
            std::copy(cStrResultSQL_, cStrResultSQL_ + cStrResultSQLSize_, quotedResultSQL_.begin() + 1 );
            wrappedLine_.push_back( quotedResultSQL_ );
        }
        ::sqlite3_free( cStrResultSQL_ );
        sqlitePrintfGuard_.Release();
        
        ++i_;
    }
    
    std::string ss;

    const char* const delim = ",";
    unsigned long stringLength = 0;
    
    for (std::vector<std::string>::iterator it = wrappedLine_.begin() ; it != wrappedLine_.end(); ++it)
    {
        stringLength += sizeof(char);
        std::string word = *it;
        stringLength += word.size();
    }
    if ( stringLength > 0 )
        stringLength -= sizeof(char);
    
    ss.reserve( stringLength );

    for (std::vector<std::string>::iterator it = wrappedLine_.begin() ; it != wrappedLine_.end(); ++it)
    {
        if( it != wrappedLine_.begin() )
        {
            ss.append( delim );
        }
        std::string word = *it;
        ss.append( word );
    }
 

    return ss;
}

@end
