USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspLogErrorDetailInsertOut2
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Description: This procedure will insert a error record local to this schema
   Tables: [error].[ErrorDetail]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [error].[uspLogErrorDetailInsertOut2](
    @psSchemaName SYSNAME
	,@pnvProcessKey NVARCHAR(25)
   ,@piErrorDetailId INT OUTPUT
)AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @ErrorDetail TABLE (
	    [ErrorDetailId] [bigint] 
	   ,[SchemaName] [sysname]
	   ,[ErrorNumber] [int]
	   ,[ErrorSeverity] [int] 
	   ,[ErrorState] [int]
	   ,[ErrorProcedure] [nvarchar](126)
	   ,[ErrorLine] [int]
	   ,[ErrorMessage] [nvarchar](2048)
	   ,[ErrorDate] [datetime2](7)
   );
   INSERT INTO [error].[ErrorDetail]
      OUTPUT Inserted.ErrorDetailId
         ,Inserted.SchemaName
         ,Inserted.ErrorNumber
         ,Inserted.ErrorSeverity
         ,Inserted.ErrorState
         ,Inserted.ErrorProcedure
         ,Inserted.ErrorLine
         ,Inserted.ErrorMessage
         ,Inserted.ErrorDate
      INTO @ErrorDetail
   SELECT
       @psSchemaName
      ,ERROR_NUMBER()
      ,ERROR_SEVERITY()
      ,ERROR_STATE()
      ,ERROR_PROCEDURE()
      ,ERROR_LINE()
      ,@pnvProcessKey+' '+ ISNULL(ERROR_MESSAGE(),'')
      ,SYSDATETIME();
   SELECT @piErrorDetailId = ErrorDetailId
   FROM @ErrorDetail;
END
