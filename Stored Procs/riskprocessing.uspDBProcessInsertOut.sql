USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspDBProcessInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[DBProcess]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspDBProcessInsertOut](
    @pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(128)
   ,@pnvDescr NVARCHAR(255)
   ,@pnvObjectFullName NVARCHAR(255)
	,@pnvRetrievalType NVARCHAR(25)
	,@pnvRetrievalCode NVARCHAR(25)
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piDBProcessId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @DBProcess table (
       DBProcessId int
      ,Code nvarchar(25)
      ,Name nvarchar(128)
      ,Descr nvarchar(255)
		,ObjectFullName nvarchar(255)
		,RetrievalType nvarchar(25)
		,RetrievalCode nvarchar(25)
      ,StatusFlag int
      ,DateActivated datetime2(7)
      ,UserName nvarchar(100)
		);
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   --Will Not update this DBProcess to a DBProcess already in use
   IF NOT EXISTS(SELECT 'X' 
                  FROM [riskprocessing].[DBProcess]
                  WHERE (Name = @pnvName
                        OR Code = @pnvCode)
                  )
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[DBProcess]
            OUTPUT inserted.DBProcessId
               ,inserted.Code
               ,inserted.Name
               ,inserted.Descr
					,inserted.ObjectFullName
					,inserted.RetrievalType
					,inserted.RetrievalCode
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @DBProcess
         SELECT @pnvCode
            ,@pnvName
            ,@pnvDescr
				,@pnvObjectFullName
				,@pnvRetrievalType
				,@pnvRetrievalCode
            ,@piStatusFlag
            ,SYSDATETIME()
            ,@pnvUserName; 
      END TRY
      BEGIN CATCH
         IF @@TRANCOUNT > @iCurrentTransactionLevel
            ROLLBACK TRANSACTION;
         EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
         SET @piDBProcessId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
      END CATCH;
      IF @@TRANCOUNT > @iCurrentTransactionLevel
      BEGIN
         COMMIT TRANSACTION;
         SELECT @piDBProcessId = DBProcessId
         FROM @DBProcess
      END
   END
   ELSE
      SELECT @piDBProcessID = -3      
END
